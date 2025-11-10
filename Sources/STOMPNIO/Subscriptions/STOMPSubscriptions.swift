import Logging
import NIOCore
import Synchronization

@usableFromInline
struct STOMPSubscriptions {
    var subscriptionIDMap: [Int: SubscriptionRef]
    private var subscriptionMap: [String: STOMPDestinationStateMachine<SubscriptionRef>]
    let logger: Logger

    static let globalSubscriptionID = Atomic<Int>(0)

    init(logger: Logger) {
        self.subscriptionIDMap = [:]
        self.logger = logger
        self.subscriptionMap = [:]
    }

    /// We received a message
    mutating func notify(_ message: STOMPFrame) throws {
        guard let destination = message.headers.first(where: { $0.name == "destination" })?.value else {
            let error = STOMPClientError.missingHeader(message: "MESSAGE frame doesn't have a destination header")
            // Push error to all subscriptions on this destination.
            // We're about to close the destination, we should tell them why
            for subscription in self.subscriptionIDMap.values {
                subscription.sendError(error)
            }
            self.subscriptionIDMap = [:]
            throw error
        }

        self.logger.trace("Received MESSAGE", metadata: ["subscription": "\(destination)"])

        switch self.subscriptionMap[destination]?.receivedMessage() {
        case .forwardMessage(let subscriptions):
            for subscription in subscriptions {
                subscription.sendMessage(message)
            }
        case .doNothing, .none:
            self.logger.trace("Received message for inactive subscription", metadata: ["subscription": "\(destination)"])
        }
    }

    /// Connection is closing, let's inform all the subscriptions
    mutating func close(error: any Error) {
        for subscription in subscriptionIDMap.values {
            subscription.sendError(error)
        }
        self.subscriptionIDMap = [:]
        self.subscriptionMap = [:]
    }

    static func getSubscriptionID() -> Int {
        Self.globalSubscriptionID.wrappingAdd(1, ordering: .relaxed).newValue
    }

    enum SubscribeAction {
        case doNothing(Int)
        case subscribe(SubscriptionRef, String)
    }

    /// Add subscription to destination.
    mutating func addSubscription(
        continuation: STOMPSubscription.Continuation,
        destination: String,
        ackMode: STOMPAckMode
    ) -> SubscribeAction {
        let id = Self.getSubscriptionID()
        let subscription = SubscriptionRef(
            id: id,
            continuation: continuation,
            destination: destination,
            ackMode: ackMode,
            logger: self.logger
        )
        subscriptionIDMap[id] = subscription
        var action = SubscribeAction.doNothing(id)
        switch subscriptionMap[destination, default: .init()].add(subscription: subscription) {
        case .subscribe:
            action = .subscribe(subscription, destination)
        case .doNothing:
            break
        }
        return action
    }

    enum UnsubscribeAction {
        case doNothing
        case unsubscribe(String)
    }

    /// Add unsubscribe
    ///
    /// Remove subscription from all the message destinations.
    /// If a message destination ends up with no subscriptions, then add it to the list of destinations to unsubscribe from.
    mutating func unsubscribe(id: Int) -> UnsubscribeAction {
        var action: UnsubscribeAction = .doNothing
        guard let subscription = subscriptionIDMap[id] else { return .doNothing }
        switch self.subscriptionMap[subscription.destination]?.close(subscription: subscription) {
        case .unsubscribe:
            action = .unsubscribe(subscription.destination)
            self.subscriptionMap.removeValue(forKey: subscription.destination)
        case .doNothing, .none:
            break
        }
        self.subscriptionIDMap[id] = nil
        return action
    }

    /// Remove subscription
    mutating func removeSubscription(id: Int) {
        guard let subscription = subscriptionIDMap[id] else { return }
        switch self.subscriptionMap[subscription.destination]?.close(subscription: subscription) {
        case .doNothing, .none:
            break
        case .unsubscribe:
            self.subscriptionMap[subscription.destination] = nil
        }
        subscriptionIDMap[id] = nil
    }

    /// Check if the subscription requires acknowledgment
    ///
    /// - Parameter id: The subscription ID
    ///
    /// - Returns: A Boolean value indicating whether the subscription requires acknowledgment
    func shouldAcknowledge(id: Int) -> Bool {
        guard let subscription = subscriptionIDMap[id] else { return false }
        return subscription.ackMode != .auto
    }
}

/// Individual subscription associated with one SUBSCRIBE frame
final class SubscriptionRef: Identifiable {
    let id: Int
    let destination: String
    let ackMode: STOMPAckMode
    let continuation: STOMPSubscription.Continuation
    let logger: Logger

    init(id: Int, continuation: STOMPSubscription.Continuation, destination: String, ackMode: STOMPAckMode, logger: Logger) {
        self.id = id
        self.destination = destination
        self.ackMode = ackMode
        self.continuation = continuation
        self.logger = logger
    }

    func sendMessage(_ message: STOMPFrame) {
        self.continuation.yield(message)
    }

    func sendError(_ error: any Error) {
        self.continuation.finish(throwing: error)
    }

    func finish() {
        self.continuation.finish()
    }
}
