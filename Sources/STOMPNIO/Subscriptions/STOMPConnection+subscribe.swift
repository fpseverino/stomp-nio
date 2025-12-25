extension STOMPConnection {
    /// Subscribe to a destination.
    ///
    /// The subscription is automatically unsubscribed when the `process` closure returns or throws.
    ///
    /// - Parameters:
    ///   - destination: The destination to subscribe to
    ///   - ackMode: The acknowledgment mode for the subscription
    ///   - userDefinedHeaders: Additional headers to include in the `SUBSCRIBE` and `UNSUBSCRIBE` frames
    ///   - process: Closure where messages received from the subscription are processed.
    ///     The closure receives a ``STOMPSubscription`` `AsyncSequence` to listen for messages.
    @inlinable
    public nonisolated func subscribe<Value>(
        to destination: String,
        ackMode: STOMPAckMode = .auto,
        userDefinedHeaders: [STOMPHeader] = [],
        process: (STOMPSubscription) async throws -> Value
    ) async throws -> Value {
        let (id, stream) = try await self.subscribe(destination: destination, ackMode: ackMode, userDefinedHeaders: userDefinedHeaders)
        let value: Value
        do {
            value = try await process(stream)
            try Task.checkCancellation()
        } catch {
            // call unsubscribe in unstructured Task to avoid it being cancelled
            _ = await Task {
                try await self.unsubscribe(id: id, userDefinedHeaders: userDefinedHeaders)
            }.result
            throw error
        }
        // call unsubscribe in unstructured Task to avoid it being cancelled
        _ = try await Task {
            try await self.unsubscribe(id: id, userDefinedHeaders: userDefinedHeaders)
        }.value
        return value
    }

    @usableFromInline
    func subscribe(
        destination: String,
        ackMode: STOMPAckMode,
        userDefinedHeaders: [STOMPHeader]
    ) async throws -> (UInt, STOMPSubscription) {
        let (stream, streamContinuation) = STOMPSubscription.makeStream()
        if Task.isCancelled {
            throw STOMPClientError.cancelledTask
        }
        let subscriptionID: UInt = try await withCheckedThrowingContinuation(isolation: self) { continuation in
            self.channelHandler.subscribe(
                streamContinuation: streamContinuation,
                destination: destination,
                ackMode: ackMode,
                userDefinedHeaders: userDefinedHeaders,
                promise: .swift(continuation),
                requestID: Self.requestIDGenerator.next()
            )
        }
        return (subscriptionID, stream)
    }

    @usableFromInline
    func unsubscribe(id: UInt, userDefinedHeaders: [STOMPHeader]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.channelHandler.unsubscribe(
                id: id,
                userDefinedHeaders: userDefinedHeaders,
                promise: .swift(continuation),
                requestID: Self.requestIDGenerator.next()
            )
        }
    }
}
