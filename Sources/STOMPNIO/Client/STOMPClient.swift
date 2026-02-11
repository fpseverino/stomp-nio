public import Logging
public import NIOCore
public import NIOPosix
import Synchronization
import _STOMPConnectionPool

#if ServiceLifecycle
public import ServiceLifecycle
#endif

/// A STOMP client that is backed by an underlying connection pool. Use ``STOMPClientConfiguration`` to change the client's behavior.
public final class STOMPClient: Sendable {
    typealias Pool = ConnectionPool<
        STOMPConnection,
        STOMPConnection.ID,
        ConnectionIDGenerator,
        ConnectionRequest<STOMPConnection>,
        ConnectionRequest.ID,
        NoOpKeepAliveBehavior<STOMPConnection>,
        STOMPClientMetrics,
        ContinuousClock
    >

    /// Connection pool
    let connectionPool: Pool
    /// Connection factory
    let connectionFactory: STOMPConnectionFactory
    /// EventLoopGroup to use
    let eventLoopGroup: any EventLoopGroup
    /// Logger
    let logger: Logger
    /// Running atomic
    let runningAtomic: Atomic<Bool>

    /// Creates a new ``STOMPClient``. Don't forget to run ``STOMPClient/run()`` the client in a long running task.
    ///
    /// - Parameters:
    ///   - address: The STOMP server address.
    ///   - configuration: The client's configuration. See ``STOMPClientConfiguration`` for details.
    ///   - eventLoopGroup: The underlying NIO `EventLoopGroup` to run client on.
    ///   - logger: The `Logger` to log messages to.
    public convenience init(
        _ address: STOMPServerAddress,
        configuration: STOMPClientConfiguration = .init(),
        eventLoopGroup: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton,
        logger: Logger
    ) {
        self.init(
            address,
            connectionIDGenerator: ConnectionIDGenerator(),
            connectionFactory: STOMPConnectionFactory(configuration: configuration),
            eventLoopGroup: eventLoopGroup,
            logger: logger
        )
    }

    private init(
        _ address: STOMPServerAddress,
        connectionIDGenerator: ConnectionIDGenerator,
        connectionFactory: STOMPConnectionFactory,
        eventLoopGroup: any EventLoopGroup,
        logger: Logger
    ) {
        var poolConfiguration = _STOMPConnectionPool.ConnectionPoolConfiguration()
        poolConfiguration.minimumConnectionCount = connectionFactory.configuration.connectionPool.minimumConnectionCount
        poolConfiguration.maximumConnectionSoftLimit = connectionFactory.configuration.connectionPool.maximumConnectionSoftLimit
        poolConfiguration.maximumConnectionHardLimit = connectionFactory.configuration.connectionPool.maximumConnectionHardLimit
        poolConfiguration.idleTimeout = connectionFactory.configuration.connectionPool.idleTimeout
        poolConfiguration.circuitBreakerTripAfter = connectionFactory.configuration.connectionPool.circuitBreakerTripAfter
        poolConfiguration.maximumConcurrentConnectionRequests = connectionFactory.configuration.connectionPool.maximumConcurrentConnectionRequests

        self.connectionPool = .init(
            configuration: poolConfiguration,
            idGenerator: connectionIDGenerator,
            requestType: ConnectionRequest<STOMPConnection>.self,
            keepAliveBehavior: .init(connectionType: STOMPConnection.self),
            observabilityDelegate: STOMPClientMetrics(logger: logger),
            clock: .continuous
        ) { (connectionID, pool) in
            var logger = logger
            logger[metadataKey: "stomp_connection_id"] = "\(connectionID)"

            let connection = try await connectionFactory.makeConnection(
                address: address,
                connectionID: connectionID,
                eventLoop: eventLoopGroup.any(),
                logger: logger
            )

            return ConnectionAndMetadata(connection: connection, maximalStreamsOnConnection: 1)
        }
        self.connectionFactory = connectionFactory
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
        self.runningAtomic = .init(false)
    }
}

extension STOMPClient {
    /// The structured root task for the client's background work.
    ///
    /// > Warning:
    /// Users must call this function in order to allow the client to process any background work. Executing queries,
    /// prepared statements or leasing connections will hang until the developer executes the client's ``run()``
    /// method.
    ///
    /// Cancelling the task which executes the ``run()`` method, is equivalent to closing the client. Once the task
    /// has been cancelled the client is not able to process any new queries or prepared statements.
    ///
    /// > Note:
    /// ``STOMPClient`` implements [ServiceLifecycle](https://github.com/swift-server/swift-service-lifecycle)'s `Service` protocol,
    /// if the `ServiceLifecycle` package trait is enabled (by default it is).
    /// Because of this ``STOMPClient`` can be passed to a `ServiceGroup` for easier lifecycle management.
    public func run() async {
        let atomicOp = self.runningAtomic.compareExchange(expected: false, desired: true, ordering: .relaxed)
        precondition(!atomicOp.original, "STOMPClient.run() should just be called once!")
        #if ServiceLifecycle
        await cancelWhenGracefulShutdown {
            await self.connectionPool.run()
        }
        #else
        await self.connectionPool.run()
        #endif
    }

    /// Get a connection from connection pool and run operation using it.
    ///
    /// - Parameter operation: Closure handling the ``STOMPConnection``.
    ///
    /// - Returns: Value returned by the closure.
    public func withConnection<Value>(
        operation: (STOMPConnection) async throws -> sending Value
    ) async throws -> Value {
        let lease: ConnectionLease<STOMPConnection>
        do {
            lease = try await self.connectionPool.leaseConnection()
        } catch let error as ConnectionPoolError {
            switch error {
            case .requestCancelled:
                throw STOMPClientError.cancelledTask
            case .poolShutdown:
                throw STOMPClientError.clientIsShutDown
            case .connectionCreationCircuitBreakerTripped:
                throw STOMPClientError.connectionCreationCircuitBreakerTripped
            default:
                throw error
            }
        }
        defer { lease.release() }
        return try await operation(lease.connection)
    }
}

extension STOMPClient {
    /// Send a STOMP frame to the server.
    ///
    /// If the frame contains a `receipt` header, this method waits for the corresponding `RECEIPT` frame from the server and returns it.
    /// If the frame does not contain a `receipt` header, the method returns `nil` immediately after sending the frame.
    ///
    /// - Parameter frame: The STOMP frame to send
    ///
    /// - Returns: The `RECEIPT` frame from the server if the sent frame contained a `receipt` header, otherwise `nil`
    @inlinable
    public func send(frame: STOMPFrame) async throws -> STOMPFrame? {
        try await self.withConnection { connection in
            try await connection.send(frame: frame)
        }
    }

    /// Send a message to a destination.
    ///
    /// - Parameters:
    ///   - body: The body of the message.
    ///   - destination: The destination to send the message to.
    ///   - contentType: The content type of the message.
    ///   - userDefinedHeaders: Additional headers to include in the `SEND` frame.
    public func send(
        _ body: ByteBuffer,
        to destination: String,
        contentType: String,
        userDefinedHeaders: STOMPHeaders = [:]
    ) async throws {
        try await self.withConnection { connection in
            try await connection.send(
                body,
                to: destination,
                contentType: contentType,
                userDefinedHeaders: userDefinedHeaders
            )
        }
    }

    /// Send a text message to a destination.
    ///
    /// - Parameters:
    ///   - body: The body of the message.
    ///   - destination: The destination to send the message to.
    ///   - contentType: The content type of the message. Defaults to `text/plain`.
    ///   - userDefinedHeaders: Additional headers to include in the `SEND` frame.
    public func send(
        _ body: String,
        to destination: String,
        contentType: String = "text/plain",
        userDefinedHeaders: STOMPHeaders = [:]
    ) async throws {
        try await self.withConnection { connection in
            try await connection.send(
                body,
                to: destination,
                contentType: contentType,
                userDefinedHeaders: userDefinedHeaders
            )
        }
    }
}

#if ServiceLifecycle
extension STOMPClient: Service {}
#endif
