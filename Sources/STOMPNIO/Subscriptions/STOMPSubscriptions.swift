import Logging
import NIOCore
import Synchronization

@usableFromInline
struct STOMPSubscriptions {
    var subscriptionIDMap: [UInt: SubscriptionRef]
    let logger: Logger

    static let globalSubscriptionID = Atomic<UInt>(0)

    init(logger: Logger) {
        self.subscriptionIDMap = [:]
        self.logger = logger
    }

    /// We received a message
    mutating func notify(_ message: STOMPFrame) throws {
        guard let subscriptionHeader = message.headers[.subscription] else {
            let error = STOMPClientError.missingHeader(message: "MESSAGE frame doesn't have a subscription header")
            // Push error to all subscriptions on this destination.
            // We're about to close the destination, we should tell them why
            for subscription in self.subscriptionIDMap.values {
                subscription.sendError(error)
            }
            self.subscriptionIDMap = [:]
            throw error
        }

        self.logger.trace("Received MESSAGE", metadata: ["subscriptionID": "\(subscriptionHeader)"])

        guard let subscriptionID = UInt(subscriptionHeader),
            let subscription = self.subscriptionIDMap[subscriptionID]
        else {
            let error = STOMPClientError.unsolicitedFrame(message: "No subscription found for id \(subscriptionHeader)")
            for subscription in self.subscriptionIDMap.values {
                subscription.sendError(error)
            }
            self.subscriptionIDMap = [:]
            throw error
        }

        subscription.sendMessage(message)
    }

    /// Connection is closing, let's inform all the subscriptions
    mutating func close(error: any Error) {
        for subscription in subscriptionIDMap.values {
            subscription.sendError(error)
        }
        self.subscriptionIDMap = [:]
    }

    static func getSubscriptionID() -> UInt {
        Self.globalSubscriptionID.wrappingAdd(1, ordering: .relaxed).newValue
    }

    /// Add subscription to destination.
    mutating func addSubscription(
        continuation: STOMPSubscription.Continuation,
        destination: String,
        ackMode: STOMPSubscription.AckMode,
        transactionID: String?
    ) -> SubscriptionRef {
        let id = Self.getSubscriptionID()
        let subscription = SubscriptionRef(
            id: id,
            continuation: continuation,
            ackMode: ackMode,
            transactionID: transactionID
        )
        self.subscriptionIDMap[id] = subscription
        return subscription
    }

    /// Remove subscription
    mutating func removeSubscription(id: UInt) {
        self.subscriptionIDMap[id] = nil
    }

    /// Check if the subscription requires acknowledgment
    ///
    /// - Parameter id: The subscription ID
    ///
    /// - Returns: A Boolean value indicating whether the subscription requires acknowledgment
    func shouldAcknowledge(id: UInt) -> Bool {
        guard let subscription = self.subscriptionIDMap[id] else { return false }
        return subscription.ackMode != .auto
    }

    /// If the subscription is part of a transaction, return its ID
    ///
    /// - Parameter id: The subscription ID
    ///
    /// - Returns: The transaction ID, or `nil` if the subscription is not part of a transaction
    func transactionID(for id: UInt) -> String? {
        self.subscriptionIDMap[id]?.transactionID
    }
}

/// Individual subscription associated with one SUBSCRIBE frame
final class SubscriptionRef: Identifiable {
    let id: UInt
    let ackMode: STOMPSubscription.AckMode
    let transactionID: String?
    let continuation: STOMPSubscription.Continuation

    init(id: UInt, continuation: STOMPSubscription.Continuation, ackMode: STOMPSubscription.AckMode, transactionID: String?) {
        self.id = id
        self.ackMode = ackMode
        self.transactionID = transactionID
        self.continuation = continuation
    }

    func sendMessage(_ message: STOMPFrame) {
        self.continuation.yield(message)
    }

    func sendError(_ error: any Error) {
        self.continuation.finish(throwing: error)
    }
}
