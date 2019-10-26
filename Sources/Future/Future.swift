import Foundation

public final class Future<Success, Failure: Error> {
    private typealias Handler = (Result<Success, Failure>) -> Void
    private typealias Task = (@escaping (Result<Success, Failure>) -> Void) -> Void

    private enum State {
        case pending([Handler], Task)
        case running([Handler])
        case resolved(Result<Success, Failure>)

        var isPending: Bool {
            if case .pending = self {
                return true
            }

            return false
        }

        mutating func addOrExecuteHandler(_ handler: @escaping Handler) {
            switch self {
            case .pending(var handlers, let task):
                handlers.append(handler)

                self = .pending(handlers, task)
            case .running(var handlers):
                handlers.append(handler)

                self = .running(handlers)
            case .resolved(let result):
                handler(result)
            }
        }

        /// Transitions from a `pending` to a `running` state.
        mutating func start() -> Task {
            switch self {
            case .pending(let handlers, let task):
                self = .running(handlers)

                return task
            case .running:
                fatalError("Already running.")
            case .resolved:
                fatalError("Already resolved.")
            }
        }

        /// Transitions from a `running` to a `resolved` state.
        mutating func resolve(result: Result<Success, Failure>) {
            switch self {
            case .pending:
                fatalError("Not running.")
            case .running(let handlers):
                handlers.forEach { $0(result) }

                self = .resolved(result)
            case .resolved:
                fatalError("Already resolved.")
            }
        }
    }

    @Atomic private var state: State

    private init(state: State) {
        _state = Atomic(state)
    }

    public func done(on target: DispatchQueue = .global(), handler: @escaping (Result<Success, Failure>) -> Void) {
        let wrapped: (Result<Success, Failure>) -> Void = { result in
            target.async {
                handler(result)
            }
        }

        var task: Task?

        $state.atomically { value in
            value.addOrExecuteHandler(wrapped)

            guard value.isPending else { return }

            task = value.start()
        }

        task? { result in
            self.state.resolve(result: result)
        }
    }

    public func map<NewSuccess>(on target: DispatchQueue = .global(), transform: @escaping (Success) -> NewSuccess) -> Future<NewSuccess, Failure> {
        Future<NewSuccess, Failure> { resolve in
            self.done(on: target) { result in
                resolve(result.map(transform))
            }
        }
    }

    public func mapError<NewFailure: Error>(on target: DispatchQueue = .global(), transform: @escaping (Failure) -> NewFailure) -> Future<Success, NewFailure> {
        Future<Success, NewFailure> { resolve in
            self.done(on: target) { result in
                resolve(result.mapError(transform))
            }
        }
    }

    public func flatMap<NewSuccess>(on target: DispatchQueue = .global(), transform: @escaping (Success) -> Future<NewSuccess, Failure>) -> Future<NewSuccess, Failure> {
        Future<NewSuccess, Failure> { resolve in
            self.done { result in
                switch result {
                case let .success(value):
                    target.async {
                        let inner = transform(value)

                        inner.done {
                            resolve($0)
                        }
                    }
                case let .failure(errur):
                    resolve(.failure(errur))
                }
            }
        }
    }

    public func flatMapError<NewFailure: Error>(on target: DispatchQueue = .global(), transform: @escaping (Failure) -> Future<Success, NewFailure>) -> Future<Success, NewFailure> {
        Future<Success, NewFailure> { resolve in
            self.done { result in
                switch result {
                case let .success(value):
                    resolve(.success(value))
                case let .failure(error):
                    target.async {
                        let inner = transform(error)

                        inner.done {
                            resolve($0)
                        }
                    }
                }
            }
        }
    }
}

extension Future {
    public convenience init(value: Success) {
        self.init(state: .resolved(.success(value)))
    }

    public convenience init(error: Failure) {
        self.init(state: .resolved(.failure(error)))
    }

    public convenience init(on target: DispatchQueue = .global(), task: @escaping (@escaping (Result<Success, Failure>) -> Void) -> Void) {
        let wrapped: (@escaping (Result<Success, Failure>) -> Void) -> Void = { resolve in
            target.async {
                task(resolve)
            }
        }

        self.init(state: .pending([], wrapped))
    }
}

extension Future where Success == Void {
    public convenience init() {
        self.init(state: .resolved(.success(())))
    }
}
