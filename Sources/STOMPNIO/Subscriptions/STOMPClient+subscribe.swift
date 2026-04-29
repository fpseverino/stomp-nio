extension STOMPClient {
    /// Run operation with the STOMP subscription connection
    ///
    /// - Parameter operation: Closure to run with subscription connection
    @inlinable
    func withSubscriptionConnection<Value>(
        _ operation: (STOMPConnection) async throws -> Value
    ) async throws -> Value {
        let id = self.subscriptionConnectionIDGenerator.next()

        let connection = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<STOMPConnection, Error>) in
                self.leaseSubscriptionConnection(id: id, request: cont)
            }
        } onCancel: {
            self.cancelSubscriptionConnection(id: id)
        }

        defer { self.releaseSubscriptionConnection(id: id) }
        return try await operation(connection)
    }

    /// Subscribe to a destination.
    /// All messages received from the subscription will be acknowledged automatically.
    /// A single connection is used for all subscriptions.
    ///
    /// The subscription is automatically unsubscribed when the `process` closure returns or throws.
    ///
    /// - Parameters:
    ///   - destination: The destination to subscribe to
    ///   - ackMode: The acknowledgment mode for the subscription
    ///   - subscribeHeaders: Additional user defined headers to include in the `SUBSCRIBE` frame
    ///   - unsubscribeHeaders: Additional user defined headers to include in the `UNSUBSCRIBE` frame
    ///   - process: Closure where messages received from the subscription are processed.
    ///     The closure receives a ``STOMPSubscription`` `AsyncSequence` to listen for messages.
    @inlinable
    public func subscribe<Value>(
        to destination: String,
        ackMode: STOMPSubscription.AckMode = .auto,
        subscribeHeaders: STOMPHeaders = [:],
        unsubscribeHeaders: STOMPHeaders = [:],
        process: (STOMPSubscription) async throws -> Value
    ) async throws -> Value {
        try await self.withSubscriptionConnection { connection in
            try await connection.subscribe(
                to: destination,
                ackMode: ackMode,
                subscribeHeaders: subscribeHeaders,
                unsubscribeHeaders: unsubscribeHeaders,
                process: process
            )
        }
    }
}
