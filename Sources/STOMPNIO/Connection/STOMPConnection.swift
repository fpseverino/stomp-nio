public import Logging
public import NIOCore
public import NIOPosix
import Synchronization

#if canImport(Network)
import Network
import NIOTransportServices
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A single connection to a STOMP server.
public final actor STOMPConnection: Sendable {
    nonisolated public let unownedExecutor: UnownedSerialExecutor

    /// Request ID generator
    @usableFromInline
    static let requestIDGenerator: IDGenerator = .init()
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
    ///   - address: Internet address of the STOMP server
    ///   - configuration: Configuration for the STOMP connection
    ///   - eventLoop: EventLoop to run connection on
    ///   - logger: Logger to use for the connection
    ///   - operation: Closure where STOMP operations using the connection are performed
    ///
    /// - Returns: The value returned by the `operation` closure
    public static func withConnection<Value>(
        address: STOMPServerAddress,
        configuration: STOMPConnectionConfiguration = .init(),
        eventLoop: any EventLoop = MultiThreadedEventLoopGroup.singleton.any(),
        logger: Logger,
        operation: (STOMPConnection) async throws -> sending Value
    ) async throws -> sending Value {
        let connection = try await self.connect(
            address: address,
            configuration: configuration,
            eventLoop: eventLoop,
            logger: logger
        )
        defer { connection.close() }
        return try await operation(connection)
    }

    /// Close connection
    public nonisolated func close() {
        guard self.isClosed.compareExchange(expected: false, desired: true, successOrdering: .relaxed, failureOrdering: .relaxed).exchanged
        else {
            return
        }
        self.channel.close(mode: .all, promise: nil)
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
    public func send(frame: STOMPFrame) async throws -> STOMPFrame? {
        guard frame.headers.contains(where: { $0.name == "receipt" }) else {
            try self.channelHandler.sendFrameNoWait(frame)
            return nil
        }

        return try await self.sendFrame(frame) { newFrame in
            newFrame.headers.first(where: { $0.name == "receipt-id" })?.value == frame.headers.first(where: { $0.name == "receipt" })?.value
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
        userDefinedHeaders: [STOMPHeader] = []
    ) async throws {
        let headers =
            userDefinedHeaders + [
                STOMPHeader(name: "destination", value: destination),
                STOMPHeader(name: "content-length", value: "\(body.readableBytes)"),
                STOMPHeader(name: "content-type", value: contentType),
                STOMPHeader(name: "receipt", value: UUID().uuidString),
            ]
        _ = try await self.send(frame: STOMPFrame(command: .send, headers: headers, body: body))
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
        userDefinedHeaders: [STOMPHeader] = []
    ) async throws {
        try await self.send(
            ByteBuffer(string: body),
            to: destination,
            contentType: contentType,
            userDefinedHeaders: userDefinedHeaders
        )
    }

    /// Trigger a graceful shutdown of the STOMP connection.
    ///
    /// This method sends a `DISCONNECT` frame to the STOMP server and waits for the `RECEIPT` frame,
    /// assuring that all previous frames have been received by the server.
    ///
    /// > Note: if the server closes its end of the socket too quickly,
    /// the client might never receive the expected `RECEIPT` frame.
    /// See the [Connection Lingering](https://stomp.github.io/stomp-specification-1.2.html#Connection_Lingering) section for more information.
    ///
    /// > Warning: Clients MUST NOT send any more frames after this method is called.
    public func triggerGracefulShutdown() async throws {
        _ = try await self.send(frame: .init(command: .disconnect, headers: [.init(name: "receipt", value: UUID().uuidString)]))
        self.channelHandler.triggerGracefulShutdown()
    }

    static func connect(
        address: STOMPServerAddress,
        configuration: STOMPConnectionConfiguration,
        eventLoop: any EventLoop = MultiThreadedEventLoopGroup.singleton.any(),
        logger: Logger
    ) async throws -> STOMPConnection {
        let future =
            if eventLoop.inEventLoop {
                self._makeConnection(
                    address: address,
                    configuration: configuration,
                    eventLoop: eventLoop,
                    logger: logger
                )
            } else {
                eventLoop.flatSubmit {
                    self._makeConnection(
                        address: address,
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

    func waitOnConnected() async throws {
        try await self.channelHandler.waitOnConnected().get()
    }

    private static func _makeConnection(
        address: STOMPServerAddress,
        configuration: STOMPConnectionConfiguration,
        eventLoop: any EventLoop,
        logger: Logger
    ) -> EventLoopFuture<STOMPConnection> {
        eventLoop.assertInEventLoop()

        let bootstrap: any NIOClientTCPBootstrapProtocol
        #if canImport(Network)
        if let tsBootstrap = createTSBootstrap(eventLoopGroup: eventLoop, tlsOptions: nil) {
            bootstrap = tsBootstrap
        } else {
            #if os(iOS) || os(tvOS)
            logger.warning(
                "Running BSD sockets on iOS or tvOS is not recommended. Please use NIOTSEventLoopGroup, to run with the Network framework"
            )
            #endif
            bootstrap = self.createSocketsBootstrap(eventLoopGroup: eventLoop)
        }
        #else
        bootstrap = self.createSocketsBootstrap(eventLoopGroup: eventLoop)
        #endif

        let connect = bootstrap.channelInitializer { channel in
            do {
                try self._setupChannel(channel, configuration: configuration, logger: logger)
                return eventLoop.makeSucceededVoidFuture()
            } catch {
                return eventLoop.makeFailedFuture(error)
            }
        }

        let future: EventLoopFuture<any Channel>
        switch address.value {
        case .hostname(let host, let port):
            future = connect.connect(host: host, port: port)
            future.whenSuccess { _ in
                logger.debug("Client connected to \(host):\(port)")
            }
        case .unixDomainSocket(let path):
            future = connect.connect(unixDomainSocketPath: path)
            future.whenSuccess { _ in
                logger.debug("Client connected to socket path \(path)")
            }
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

    package static func setupChannelAndConnect(
        _ channel: any Channel,
        configuration: STOMPConnectionConfiguration = .init(),
        logger: Logger
    ) async throws -> STOMPConnection {
        if !channel.eventLoop.inEventLoop {
            return try await channel.eventLoop.flatSubmit {
                self._setupChannelAndConnect(channel, configuration: configuration, logger: logger)
            }.get()
        }
        return try await self._setupChannelAndConnect(channel, configuration: configuration, logger: logger).get()
    }

    private static func _setupChannelAndConnect(
        _ channel: any Channel,
        configuration: STOMPConnectionConfiguration,
        logger: Logger
    ) -> EventLoopFuture<STOMPConnection> {
        do {
            return channel.connect(to: try SocketAddress(ipAddress: "127.0.0.1", port: 1883)).flatMap {
                channel.eventLoop.makeCompletedFuture {
                    let handler = try self._setupChannel(
                        channel,
                        configuration: configuration,
                        logger: logger
                    )
                    return STOMPConnection(
                        channel: channel,
                        channelHandler: handler,
                        configuration: configuration,
                        logger: logger
                    )
                }
            }
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
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

    /// Create a BSD sockets based bootstrap
    private static func createSocketsBootstrap(eventLoopGroup: any EventLoopGroup) -> ClientBootstrap {
        ClientBootstrap(group: eventLoopGroup)
    }

    #if canImport(Network)
    /// Create a NIOTransportServices bootstrap using Network.framework
    private static func createTSBootstrap(
        eventLoopGroup: any EventLoopGroup,
        tlsOptions: NWProtocolTLS.Options?
    ) -> NIOTSConnectionBootstrap? {
        guard
            let bootstrap = NIOTSConnectionBootstrap(validatingGroup: eventLoopGroup)
        else {
            return nil
        }
        if let tlsOptions {
            return bootstrap.tlsOptions(tlsOptions)
        }
        return bootstrap
    }
    #endif

    @usableFromInline
    func sendFrame(
        _ frame: STOMPFrame,
        checkInbound: @escaping @Sendable (STOMPFrame) throws -> Bool
    ) async throws -> STOMPFrame {
        let requestID = Self.requestIDGenerator.next()
        return try await withTaskCancellationHandler {
            if Task.isCancelled {
                throw STOMPClientError.cancelledTask
            }
            return try await withCheckedThrowingContinuation { continuation in
                self.channelHandler.sendFrame(frame, promise: .swift(continuation), requestID: requestID, checkInbound: checkInbound)
            }
        } onCancel: {
            self.cancel(requestID: requestID)
        }
    }

    @usableFromInline
    nonisolated func cancel(requestID: Int) {
        self.channel.eventLoop.execute {
            self.assumeIsolated { this in
                this.channelHandler.cancel(requestID: requestID)
            }
        }
    }
}
