import Logging
import NIOCore
import Synchronization
public import _STOMPConnectionPool

// Extend STOMPConnection so we can use it with the connection pool
extension STOMPConnection: PooledConnection {
    /// Connection ID
    public typealias ID = Int
    /// On close
    public nonisolated func onClose(_ closure: @escaping @Sendable ((any Error)?) -> Void) {
        self.channel.closeFuture.whenComplete { _ in closure(nil) }
    }
}

/// Connection ID generator for STOMP connection pool
@usableFromInline
package final class ConnectionIDGenerator: ConnectionIDGeneratorProtocol {
    static let globalGenerator = ConnectionIDGenerator()

    private let atomic: Atomic<Int>

    init() {
        self.atomic = .init(0)
    }

    @usableFromInline
    package func next() -> Int {
        self.atomic.wrappingAdd(1, ordering: .relaxed).oldValue
    }
}

/// STOMP client connection pool metrics
final class STOMPClientMetrics: ConnectionPoolObservabilityDelegate {
    typealias ConnectionID = STOMPConnection.ID

    let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func startedConnecting(id: ConnectionID) {
        self.logger.debug("Creating new connection", metadata: ["stomp_connection_id": "\(id)"])
    }

    /// A connection attempt failed with the given error. After some period of
    /// time ``startedConnecting(id:)`` may be called again.
    func connectFailed(id: ConnectionID, error: any Error) {
        self.logger.debug(
            "Connection creation failed",
            metadata: [
                "stomp_connection_id": "\(id)",
                "error": "\(String(reflecting: error))",
            ]
        )
    }

    func connectSucceeded(id: ConnectionID) {
        self.logger.debug("Connection established", metadata: ["stomp_connection_id": "\(id)"])
    }

    /// The utilization of the connection changed; a stream may have been used, returned or the
    /// maximum number of concurrent streams available on the connection changed.
    func connectionLeased(id: ConnectionID) {
        self.logger.debug("Connection leased", metadata: ["stomp_connection_id": "\(id)"])
    }

    func connectionReleased(id: ConnectionID) {
        self.logger.debug("Connection released", metadata: ["stomp_connection_id": "\(id)"])
    }

    func keepAliveTriggered(id: ConnectionID) {
        self.logger.debug("Run heart-beat", metadata: ["stomp_connection_id": "\(id)"])
    }

    func keepAliveSucceeded(id: ConnectionID) {}

    func keepAliveFailed(id: STOMPConnection.ID, error: any Error) {}

    /// The remote peer is quiescing the connection: no new streams will be created on it. The
    /// connection will eventually be closed and removed from the pool.
    func connectionClosing(id: ConnectionID) {
        self.logger.debug("Close connection", metadata: ["stomp_connection_id": "\(id)"])
    }

    /// The connection was closed. The connection may be established again in the future
    /// (notified via ``STOMPClientMetrics/startedConnecting(id:)``).
    func connectionClosed(id: ConnectionID, error: (any Error)?) {
        self.logger.debug("Connection closed", metadata: ["stomp_connection_id": "\(id)"])
    }

    func requestQueueDepthChanged(_ newDepth: Int) {}

    func connectSucceeded(id: STOMPConnection.ID, streamCapacity: UInt16) {}

    func connectionUtilizationChanged(id: STOMPConnection.ID, streamsUsed: UInt16, streamCapacity: UInt16) {}
}
