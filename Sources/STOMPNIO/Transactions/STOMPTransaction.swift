public import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A STOMP transaction.
public struct STOMPTransaction: Sendable {
    @usableFromInline
    let id: String
    @usableFromInline
    let connection: STOMPConnection

    /// Send a message to a destination during this transaction.
    ///
    /// - Parameters:
    ///   - body: The body of the message
    ///   - destination: The destination to send the message to
    ///   - contentType: The content type of the message
    ///   - userDefinedHeaders: Additional headers to include in the `SEND` frame
    public func send(
        _ body: ByteBuffer,
        to destination: String,
        contentType: String = "text/plain",
        userDefinedHeaders: [STOMPHeader] = []
    ) async throws {
        let headers =
            userDefinedHeaders + [
                STOMPHeader(name: "destination", value: destination),
                STOMPHeader(name: "content-length", value: "\(body.readableBytes)"),
                STOMPHeader(name: "content-type", value: contentType),
                STOMPHeader(name: "transaction", value: self.id),
            ]
        _ = try await self.connection.send(frame: STOMPFrame(command: .send, headers: headers, body: body))
    }

    /// Subscribe to a destination.
    /// All messages received from the subscription will be acknowledged as part of this transaction.
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
        ackMode: STOMPSubscription.AckMode = .auto,
        userDefinedHeaders: [STOMPHeader] = [],
        process: (STOMPSubscription) async throws -> Value
    ) async throws -> Value {
        let (id, stream) = try await self.connection.subscribe(
            destination: destination,
            ackMode: ackMode,
            userDefinedHeaders: userDefinedHeaders,
            transactionID: self.id
        )
        let value: Value
        do {
            value = try await process(stream)
            try Task.checkCancellation()
        } catch {
            // call unsubscribe in unstructured Task to avoid it being cancelled
            _ = await Task {
                try await self.connection.unsubscribe(id: id, userDefinedHeaders: userDefinedHeaders)
            }.result
            throw error
        }
        // call unsubscribe in unstructured Task to avoid it being cancelled
        _ = try await Task {
            try await self.connection.unsubscribe(id: id, userDefinedHeaders: userDefinedHeaders)
        }.value
        return value
    }
}
