public import Logging
public import NIOCore
public import NIOPosix
import Synchronization

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A single connection to a STOMP server.
public final actor STOMPConnection: Sendable {
    nonisolated public let unownedExecutor: UnownedSerialExecutor

    /// Logger used by connection
    @usableFromInline
    let logger: Logger
    @usableFromInline
    let channel: any Channel
    @usableFromInline
    let channelHandler: STOMPChannelHandler
    let configuration: STOMPConnectionConfiguration
    let isClosed: Atomic<Bool>

    init(
        channel: any Channel,
        channelHandler: STOMPChannelHandler,
        configuration: STOMPConnectionConfiguration,
        logger: Logger
    ) {
        self.unownedExecutor = channel.eventLoop.executor.asUnownedSerialExecutor()
        self.channel = channel
        self.channelHandler = channelHandler
        self.configuration = configuration
        self.logger = logger
        self.isClosed = .init(false)
    }

    /// Connect to the STOMP server and run operations using the connection, then it automatically closes the connection.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address of the STOMP server
    ///   - port: The port on which the STOMP server is listening
    ///   - configuration: Configuration for the STOMP connection
    ///   - eventLoop: EventLoop to run connection on
    ///   - logger: Logger to use for the connection
    ///   - isolation: Actor isolation
    ///   - operation: Closure where STOMP operations using the connection are performed
    ///
    /// - Returns: The value returned by the `operation` closure
    public static func withConnection<Value>(
        host: String,
        port: Int,
        configuration: STOMPConnectionConfiguration = .init(),
        eventLoop: any EventLoop = MultiThreadedEventLoopGroup.singleton.any(),
        logger: Logger,
        isolation: isolated (any Actor)? = #isolation,
        operation: (STOMPConnection) async throws -> sending Value
    ) async throws -> sending Value {
        let connection = try await self.connect(
            host: host,
            port: port,
            configuration: configuration,
            eventLoop: eventLoop,
            logger: logger
        )
        defer { connection.close() }
        return try await operation(connection)
    }

    static func connect(
        host: String,
        port: Int,
        configuration: STOMPConnectionConfiguration,
        eventLoop: any EventLoop = MultiThreadedEventLoopGroup.singleton.any(),
        logger: Logger
    ) async throws -> STOMPConnection {
        let future =
            if eventLoop.inEventLoop {
                self._makeConnection(
                    host: host,
                    port: port,
                    configuration: configuration,
                    eventLoop: eventLoop,
                    logger: logger
                )
            } else {
                eventLoop.flatSubmit {
                    self._makeConnection(
                        host: host,
                        port: port,
                        configuration: configuration,
                        eventLoop: eventLoop,
                        logger: logger
                    )
                }
            }
        let connection = try await future.get()
        try await connection.waitOnConnected()
        return connection
    }

    /// Close connection
    public nonisolated func close() {
        guard self.isClosed.compareExchange(expected: false, desired: true, successOrdering: .relaxed, failureOrdering: .relaxed).exchanged
        else {
            return
        }
        self.channel.close(mode: .all, promise: nil)
    }

    func waitOnConnected() async throws {
        try await self.channelHandler.waitOnConnected().get()
    }

    private static func _makeConnection(
        host: String,
        port: Int,
        configuration: STOMPConnectionConfiguration,
        eventLoop: any EventLoop,
        logger: Logger
    ) -> EventLoopFuture<STOMPConnection> {
        eventLoop.assertInEventLoop()

        let bootstrap: any NIOClientTCPBootstrapProtocol
        bootstrap = ClientBootstrap(group: eventLoop)

        let connect = bootstrap.channelInitializer { channel in
            do {
                try self._setupChannel(channel, configuration: configuration, logger: logger)
                return eventLoop.makeSucceededVoidFuture()
            } catch {
                return eventLoop.makeFailedFuture(error)
            }
        }

        let future: EventLoopFuture<any Channel>
        future = connect.connect(host: host, port: port)
        future.whenSuccess { _ in
            logger.debug("Client connected to \(host):\(port)")
        }

        return future.flatMapThrowing { channel in
            let handler = try channel.pipeline.syncOperations.handler(type: STOMPChannelHandler.self)
            return STOMPConnection(
                channel: channel,
                channelHandler: handler,
                configuration: configuration,
                logger: logger
            )
        }
    }

    @discardableResult
    static func _setupChannel(
        _ channel: any Channel,
        configuration: STOMPConnectionConfiguration,
        logger: Logger
    ) throws -> STOMPChannelHandler {
        channel.eventLoop.assertInEventLoop()
        let sync = channel.pipeline.syncOperations
        let stompChannelHandler = STOMPChannelHandler(
            configuration: .init(configuration),
            eventLoop: channel.eventLoop,
            logger: logger
        )
        try sync.addHandler(stompChannelHandler)
        return stompChannelHandler
    }

    @usableFromInline
    func sendFrame(
        _ frame: STOMPFrame,
        checkInbound: @escaping @Sendable (STOMPFrame) throws -> Bool
    ) async throws -> STOMPFrame {
        try await withCheckedThrowingContinuation { continuation in
            self.channelHandler.sendFrame(frame, promise: .swift(continuation), checkInbound: checkInbound)
        }
    }

    /// Send a STOMP frame to the server.
    ///
    /// If the frame contains a `receipt` header, this method waits for the corresponding `RECEIPT` frame from the server and returns it.
    /// If the frame does not contain a `receipt` header, the method returns `nil` immediately after sending the frame.
    ///
    /// - Parameter frame: The STOMP frame to send
    ///
    /// - Returns: The `RECEIPT` frame from the server if the sent frame contained a `receipt` header, otherwise `nil`
    @inlinable
    public func execute(frame: STOMPFrame) async throws -> STOMPFrame? {
        guard frame.headers.contains(where: { $0.name == "receipt" }) else {
            try await self.channel.writeAndFlush(frame)
            return nil
        }

        return try await self.sendFrame(frame) { newFrame in
            newFrame.headers.first(where: { $0.name == "receipt-id" })?.value == frame.headers.first(where: { $0.name == "receipt" })?.value
        }
    }

    /// Send a message to a destination.
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
                STOMPHeader(name: "receipt", value: UUID().uuidString),
            ]
        _ = try await self.execute(frame: STOMPFrame(command: .send, headers: headers, body: body))
    }

    /// Subscribe to a destination.
    ///
    /// The subscription is automatically unsubscribed when the `process` closure returns or throws.
    ///
    /// - Parameters:
    ///   - destination: The destination to subscribe to
    ///   - ackMode: The acknowledgment mode for the subscription
    ///   - userDefinedHeaders: Additional headers to include in the `SUBSCRIBE` and `UNSUBSCRIBE` frames
    ///   - isolation: Actor isolation
    ///   - process: Closure where messages received from the subscription are processed.
    ///     The closure receives a ``STOMPSubscription`` `AsyncSequence` to listen for messages.
    public func subscribe<Value>(
        to destination: String,
        ackMode: STOMPAckMode = .auto,
        userDefinedHeaders: [STOMPHeader] = [],
        isolation: isolated (any Actor)? = #isolation,
        process: (STOMPSubscription) async throws -> sending Value
    ) async throws -> sending Value {
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
    ) async throws -> (Int, STOMPSubscription) {
        let (stream, streamContinuation) = STOMPSubscription.makeStream()
        if Task.isCancelled {
            throw STOMPClientError.cancelledTask
        }
        let subscriptionID: Int = try await withCheckedThrowingContinuation { continuation in
            self.channelHandler.subscribe(
                streamContinuation: streamContinuation,
                destination: destination,
                ackMode: ackMode,
                userDefinedHeaders: userDefinedHeaders,
                promise: .swift(continuation)
            )
        }
        return (subscriptionID, stream)
    }

    @usableFromInline
    func unsubscribe(id: Int, userDefinedHeaders: [STOMPHeader]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.channelHandler.unsubscribe(id: id, userDefinedHeaders: userDefinedHeaders, promise: .swift(continuation))
        }
    }
}
