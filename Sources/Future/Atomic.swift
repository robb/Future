import Foundation

@propertyWrapper
public final class Atomic<Value> {
    private let lock: os_unfair_lock_t

    public var projectedValue: Atomic<Value> {
        self
    }

    private var underlying: Value

    public var wrappedValue: Value {
        get {
            atomically { $0 }
        }
        set {
            atomically { $0 = newValue }
        }
    }

    public init(_ value: Value) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())

        self.underlying = value
    }

    deinit {
        lock.deallocate()
    }

    @discardableResult
    public func atomically<T>(_ transform: (inout Value) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer {
            os_unfair_lock_unlock(lock)
        }

        return transform(&underlying)
    }
}
