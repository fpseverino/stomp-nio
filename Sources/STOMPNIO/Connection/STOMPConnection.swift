public import Logging
public import NIOCore
import NIOHTTP1
import NIOHTTPTypesHTTP1
public import NIOPosix
import NIOWebSocket
import Synchronization

#if os(macOS) || os(Linux) || os(Android)
import NIOSSL
#endif

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
    /// Connection ID, used by connection pool
    public let id: ID
    /// Logger used by connection
    @usableFromInline
    let logger: Logger
    @usableFromInline
    let channel: any Channel
    @usableFromInline
    let channelHandler: STOMPChannelHandler
    let configuration: STOMPConnectionConfiguration
    let isClosed: Atomic<Bool>

    /// Initialize connection
    init(
        channel: any Channel,
        connectionID: ID,
        channelHandler: STOMPChannelHandler,
        configuration: STOMPConnectionConfiguration,
        logger: Logger
    ) {
        self.unownedExecutor = channel.eventLoop.executor.asUnownedSerialExecutor()
        self.channel = channel
        self.channelHandler = channelHandler
        self.configuration = configuration
        self.id = connectionID
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
        operation: (STOMPConnection) async throws -> Value
    ) async throws -> Value {
        let connection = try await self.connect(
            address: address,
            connectionID: 0,
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
        guard frame.headers.contains(.receipt) else {
            try self.channelHandler.sendFrameNoWait(frame)
            return nil
        }

        return try await self.sendFrame(frame) { newFrame in
            newFrame.headers[.receiptID] == frame.headers[.receipt]
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
        let headers: STOMPHeaders =
            userDefinedHeaders + [
                .destination: destination,
                .contentLength: "\(body.readableBytes)",
                .contentType: contentType,
                .receipt: UUID().uuidString,
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
        userDefinedHeaders: STOMPHeaders = [:]
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
        _ = try await self.send(frame: .init(command: .disconnect, headers: [.receipt: UUID().uuidString]))
        self.channelHandler.triggerGracefulShutdown()
    }

    /// Send a heart-beat to the STOMP server.
    public func heartBeat() throws {
        try self.channelHandler.heartBeat()
    }

    /// Connect to STOMP broker and return connection
    ///
    /// - Parameters:
    ///   - address: Internet address of broker
    ///   - connectionID: Connection identifier, used by connection pool
    ///   - configuration: Configuration of STOMP connection
    ///   - eventLoop: `EventLoop` to run connection on
    ///   - logger: `Logger` for connection
    /// - Returns: ``STOMPConnection``
    static func connect(
        address: STOMPServerAddress,
        connectionID: ID,
        configuration: STOMPConnectionConfiguration,
        eventLoop: any EventLoop = MultiThreadedEventLoopGroup.singleton.any(),
        logger: Logger
    ) async throws -> STOMPConnection {
        let future =
            if eventLoop.inEventLoop {
                self._makeConnection(
                    address: address,
                    connectionID: connectionID,
                    configuration: configuration,
                    eventLoop: eventLoop,
                    logger: logger
                )
            } else {
                eventLoop.flatSubmit {
                    self._makeConnection(
                        address: address,
                        connectionID: connectionID,
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
        connectionID: ID,
        configuration: STOMPConnectionConfiguration,
        eventLoop: any EventLoop,
        logger: Logger
    ) -> EventLoopFuture<STOMPConnection> {
        eventLoop.assertInEventLoop()

        let host =
            switch address.value {
            case .hostname(let hostname, _):
                hostname
            case .unixDomainSocket(let path):
                path
            }

        let channelPromise = eventLoop.makePromise(of: (any Channel).self)

        do {
            let bootstrap = try Self.createBootstrap(configuration: configuration, eventLoopGroup: eventLoop, host: host, logger: logger)

            let connect = bootstrap.channelInitializer { channel in
                do {
                    if let webSocketConfiguration = configuration.webSocket {
                        // Prepare for WebSockets and on upgrade add handlers
                        let promise = eventLoop.makePromise(of: Void.self)
                        promise.futureResult.map { _ in channel }.cascade(to: channelPromise)

                        return Self._setupChannelForWebSockets(
                            channel,
                            address: address,
                            configuration: configuration,
                            webSocketConfiguration: webSocketConfiguration,
                            upgradePromise: promise
                        ) {
                            try self._setupChannel(channel, configuration: configuration, logger: logger)
                        }
                    } else {
                        try self._setupChannel(channel, configuration: configuration, logger: logger)
                    }
                    return eventLoop.makeSucceededVoidFuture()
                } catch {
                    channelPromise.fail(error)
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

            future.map { channel in
                if configuration.webSocket == nil {
                    channelPromise.succeed(channel)
                }
            }.cascadeFailure(to: channelPromise)
        } catch {
            channelPromise.fail(error)
        }

        return channelPromise.futureResult.flatMapThrowing { channel in
            let handler = try channel.pipeline.syncOperations.handler(type: STOMPChannelHandler.self)
            return STOMPConnection(
                channel: channel,
                connectionID: connectionID,
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
                        connectionID: 0,
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

    private static func _setupChannelForWebSockets(
        _ channel: any Channel,
        address: STOMPServerAddress,
        configuration: STOMPConnectionConfiguration,
        webSocketConfiguration: STOMPConnectionConfiguration.WebSocket,
        upgradePromise promise: EventLoopPromise<Void>,
        afterHandlerAdded: @Sendable @escaping () throws -> Void
    ) -> EventLoopFuture<Void> {
        var hostHeader: String {
            if case .enable(_, let sniServerName) = configuration.tls.base, let sniServerName {
                return sniServerName
            }
            switch (configuration.tls.base, address.value) {
            case (.enable, .hostname(let host, let port)) where port != 443:
                return "\(host):\(port)"
            case (.disable, .hostname(let host, let port)) where port != 80:
                return "\(host):\(port)"
            case (.enable, .hostname(let host, _)), (.disable, .hostname(let host, _)):
                return host
            case (.enable, .unixDomainSocket(let path)), (.disable, .unixDomainSocket(let path)):
                return path
            }
        }

        // Initial HTTP request handler, before upgrade
        let httpHandler = STOMPWebSocketInitialRequestChannelHandler(
            host: hostHeader,
            urlPath: webSocketConfiguration.urlPath,
            additionalHeaders: .init(webSocketConfiguration.initialRequestHeaders),
            upgradePromise: promise
        )

        // Create random request key
        let requestKey = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        let websocketUpgrader = NIOWebSocketClientUpgrader(
            requestKey: Data(requestKey).base64EncodedString(),
            maxFrameSize: webSocketConfiguration.maxFrameSize
        ) { channel, _ in
            let future = channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHandler(STOMPWebSocketChannelHandler())
                try afterHandlerAdded()
            }
            future.cascade(to: promise)
            return future
        }
        let upgradeConfig: NIOHTTPClientUpgradeSendableConfiguration = (
            upgraders: [websocketUpgrader],
            completionHandler: { _ in
                channel.pipeline.removeHandler(httpHandler, promise: nil)
            }
        )

        // Add HTTP handler with WebSocket upgrade
        return channel.pipeline.addHTTPClientHandlers(withClientUpgrade: upgradeConfig).flatMap {
            channel.pipeline.addHandler(httpHandler)
        }
    }

    private static func createBootstrap(
        configuration: STOMPConnectionConfiguration,
        eventLoopGroup: any EventLoopGroup,
        host: String,
        logger: Logger
    ) throws -> NIOClientTCPBootstrap {
        var serverName: String {
            if case .enable(_, let sniServerName) = configuration.tls.base, let sniServerName {
                sniServerName
            } else {
                host
            }
        }

        let bootstrap: NIOClientTCPBootstrap
        #if canImport(Network)
        // If the EventLoop is compatible with NIOTransportServices create a `NIOTSConnectionBootstrap`
        if let tsBootstrap = NIOTSConnectionBootstrap(validatingGroup: eventLoopGroup) {
            // Create `NIOClientTCPBootstrap` with NIOTS TLS provider
            let options: NWProtocolTLS.Options
            if case .enable(let tlsConfigType, _) = configuration.tls.base {
                switch tlsConfigType {
                case .ts(let tsConfig):
                    options = try tsConfig.getNWProtocolTLSOptions(logger: logger)
                #if os(macOS) || os(Linux) || os(Android)
                case .niossl:
                    throw STOMPClientError.wrongTLSConfig
                #endif
                }
            } else {
                options = NWProtocolTLS.Options()
            }
            sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, serverName)
            let tlsProvider = NIOTSClientTLSProvider(tlsOptions: options)
            bootstrap = NIOClientTCPBootstrap(tsBootstrap, tls: tlsProvider)
            if case .enable = configuration.tls.base {
                return bootstrap.enableTLS()
            }
            return bootstrap
        }
        #endif

        #if os(macOS) || os(Linux) || os(Android)
        if let clientBootstrap = ClientBootstrap(validatingGroup: eventLoopGroup) {
            if case .enable(let tlsConfig, _) = configuration.tls.base {
                let tlsConfiguration: TLSConfiguration
                switch tlsConfig {
                case .niossl(let config):
                    tlsConfiguration = config
                #if os(macOS)
                case .ts:
                    throw STOMPClientError.wrongTLSConfig
                #endif
                }
                let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                let tlsProvider = try NIOSSLClientTLSProvider<ClientBootstrap>(context: sslContext, serverHostname: serverName)
                bootstrap = NIOClientTCPBootstrap(clientBootstrap, tls: tlsProvider)
                return bootstrap.enableTLS()
            } else {
                bootstrap = NIOClientTCPBootstrap(clientBootstrap, tls: NIOInsecureNoTLS())
            }
            return bootstrap
        }
        #endif

        preconditionFailure("Cannot create bootstrap for the supplied EventLoop")
    }

    @usableFromInline
    func sendFrame(
        _ frame: STOMPFrame,
        checkInbound: @escaping @Sendable (STOMPFrame) throws -> Bool
    ) async throws -> STOMPFrame {
        let requestID = Self.requestIDGenerator.next()
        return try await withTaskCancellationHandler {
            if Task.isCancelled {
                throw STOMPClientError.cancelled
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
