/// A `~Copyable` continuation wrapper around `UnsafeContinuation` that enforces exactly-once fulfillment at compile time.
@usableFromInline
struct STOMPContinuation<Success, Failure: Error>: ~Copyable, Sendable {
    @usableFromInline
    let unsafeContinuation: UnsafeContinuation<Success, Failure>

    @inlinable
    init(_ unsafeContinuation: UnsafeContinuation<Success, Failure>) {
        self.unsafeContinuation = unsafeContinuation
    }

    @inlinable
    deinit {
        fatalError("This continuation was dropped.")
    }

    @inlinable
    consuming func resume(returning value: sending Success) where Failure == Never {
        self.unsafeContinuation.resume(returning: value)
        discard self
    }

    @inlinable
    consuming func resume(returning value: sending Success) {
        self.unsafeContinuation.resume(returning: value)
        discard self
    }

    @inlinable
    consuming func resume(throwing error: consuming Failure) {
        self.unsafeContinuation.resume(throwing: error)
        discard self
    }
}

@inlinable
func withSTOMPContinuation<Success>(
    of: Success.Type = Success.self,
    _ body: (consuming STOMPContinuation<Success, Never>) -> Void
) async -> Success {
    await withUnsafeContinuation { continuation in
        body(STOMPContinuation(continuation))
    }
}

@inlinable
func withSTOMPThrowingContinuation<Success>(
    of: Success.Type = Success.self,
    _ body: (consuming STOMPContinuation<Success, any Error>) -> Void
) async throws -> Success {
    try await withUnsafeThrowingContinuation { continuation in
        body(STOMPContinuation(continuation))
    }
}
