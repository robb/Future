#if os(Linux)
import Foundation

@propertyWrapper
public final class Atomic<Value> {
    private var mutex: UnsafeMutablePointer<pthread_mutex_t>

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
        mutex = .allocate(capacity: 1)

        var attr = pthread_mutexattr_t()
        pthread_mutexattr_init(&attr)
        pthread_mutexattr_settype(&attr, .init(PTHREAD_MUTEX_ERRORCHECK))

        let error = pthread_mutex_init(mutex, &attr)
        precondition(error == 0, "Failed to create pthread_mutex")

        self.underlying = value
    }

    deinit {
        let error = pthread_mutex_destroy(mutex)
        precondition(error == 0, "Failed to destroy pthread_mutex")
    }

    @discardableResult
    public func atomically<T>(_ transform: (inout Value) -> T) -> T {
        pthread_mutex_lock(mutex)
        defer {
            pthread_mutex_unlock(mutex)
        }

        return transform(&underlying)
    }
}
#else
import os

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
#endif
