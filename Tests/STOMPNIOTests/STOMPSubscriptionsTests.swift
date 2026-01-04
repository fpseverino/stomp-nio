import Logging
import NIOCore
import Testing

@testable import STOMPNIO

@Suite("STOMPSubscriptions Tests")
struct STOMPSubscriptionsTests {
    @Test("Notify", arguments: STOMPSubscription.AckMode.allCases)
    func notify(ackMode: STOMPSubscription.AckMode) async throws {
        var subscriptions = STOMPSubscriptions(logger: self.logger)
        let transactionID = "test-transaction-id"
        let destination = "/queue/test-notify"
        let (stream, continuation) = STOMPSubscription.makeStream()

        let subscriptionRef = subscriptions.addSubscription(
            continuation: continuation,
            destination: destination,
            ackMode: ackMode,
            transactionID: transactionID
        )
        let subscriptionID = subscriptionRef.id
        #expect(subscriptionID > 0)
        #expect(subscriptions.subscriptionIDMap[subscriptionID] != nil)

        switch (ackMode, subscriptions.shouldAcknowledge(id: subscriptionID)) {
        case (.auto, false), (.client, true), (.clientIndividual, true):
            break
        case (.auto, true), (.client, false), (.clientIndividual, false):
            Issue.record("shouldAcknowledge returned unexpected value for ackMode \(ackMode)")
        }

        #expect(subscriptions.transactionID(for: subscriptionID) == transactionID)

        let messageFrame = STOMPFrame(
            command: .message,
            headers: [
                .subscription: "\(subscriptionID)",
                .destination: destination,
            ],
            body: ByteBuffer(string: "Test Message")
        )
        try subscriptions.notify(messageFrame)
        let receivedMessage = try await stream.first { _ in true }
        #expect(receivedMessage == messageFrame)

        subscriptions.removeSubscription(id: subscriptionID)
        #expect(subscriptions.subscriptionIDMap[subscriptionID] == nil)
    }

    @Test("Notify without Subscription Header", arguments: STOMPSubscription.AckMode.allCases)
    func notifyWithoutSubscriptionHeader(ackMode: STOMPSubscription.AckMode) async throws {
        var subscriptions = STOMPSubscriptions(logger: self.logger)
        let transactionID = "test-transaction-id"
        let destination = "/queue/test-notify-without-header"
        let (stream, continuation) = STOMPSubscription.makeStream()

        let subscriptionRef = subscriptions.addSubscription(
            continuation: continuation,
            destination: destination,
            ackMode: ackMode,
            transactionID: transactionID
        )
        let subscriptionID = subscriptionRef.id
        #expect(subscriptionID > 0)
        #expect(subscriptions.subscriptionIDMap[subscriptionID] != nil)

        switch (ackMode, subscriptions.shouldAcknowledge(id: subscriptionID)) {
        case (.auto, false), (.client, true), (.clientIndividual, true):
            break
        case (.auto, true), (.client, false), (.clientIndividual, false):
            Issue.record("shouldAcknowledge returned unexpected value for ackMode \(ackMode)")
        }

        #expect(subscriptions.transactionID(for: subscriptionID) == transactionID)

        let messageFrame = STOMPFrame(
            command: .message,
            headers: [.destination: destination],
            body: ByteBuffer(string: "Test Message")
        )
        #expect(throws: STOMPClientError.missingHeader(message: "MESSAGE frame doesn't have a subscription header")) {
            try subscriptions.notify(messageFrame)
        }
        await #expect(throws: STOMPClientError.missingHeader(message: "MESSAGE frame doesn't have a subscription header")) {
            _ = try await stream.first { _ in true }
        }

        subscriptions.removeSubscription(id: subscriptionID)
        #expect(subscriptions.subscriptionIDMap[subscriptionID] == nil)
    }

    @Test("Notify without Subscription")
    func notifyWithoutSubscription() async throws {
        var subscriptions = STOMPSubscriptions(logger: self.logger)
        let subscriptionHeader = "test-subscription-id"
        let (stream, continuation) = STOMPSubscription.makeStream()

        // We need at least one subscription in the map
        _ = subscriptions.addSubscription(
            continuation: continuation,
            destination: "/queue/test-notify-without-subscription",
            ackMode: .auto,
            transactionID: nil
        )

        let messageFrame = STOMPFrame(
            command: .message,
            headers: [
                .subscription: subscriptionHeader,
                .destination: "/queue/test-notify-without-subscription",
            ],
            body: ByteBuffer(string: "Test Message")
        )
        #expect(throws: STOMPClientError.unsolicitedFrame(message: "No subscription found for id \(subscriptionHeader)")) {
            try subscriptions.notify(messageFrame)
        }
        await #expect(throws: STOMPClientError.unsolicitedFrame(message: "No subscription found for id \(subscriptionHeader)")) {
            _ = try await stream.first { _ in true }
        }
    }

    @Test("Close Subscriptions")
    func closeSubscriptions() async throws {
        var subscriptions = STOMPSubscriptions(logger: self.logger)
        let (stream, continuation) = STOMPSubscription.makeStream()

        let subscriptionID = subscriptions.addSubscription(
            continuation: continuation,
            destination: "/queue/test-close-subscriptions",
            ackMode: .auto,
            transactionID: nil
        ).id
        #expect(subscriptions.subscriptionIDMap[subscriptionID] != nil)

        let closeError = STOMPClientError.connectionClosed
        subscriptions.close(error: closeError)
        #expect(subscriptions.subscriptionIDMap.isEmpty)
        await #expect(throws: closeError) {
            _ = try await stream.first { _ in true }
        }
    }

    let logger: Logger = {
        var logger = Logger(label: "STOMPSubscriptionsTests")
        logger.logLevel = .trace
        return logger
    }()
}
