import Logging
import NIOCore

final class STOMPConnectionFactory: Sendable {
    enum Mode: Sendable {
        case `default`
        case custom(@Sendable (STOMPServerAddress, any EventLoop) async throws -> any Channel)
    }

    let mode: Mode
    let configuration: STOMPClientConfiguration

    init(configuration: STOMPClientConfiguration) {
        self.configuration = configuration
        self.mode = .default
    }

    init(
        configuration: STOMPClientConfiguration,
        customHandler: (@Sendable (STOMPServerAddress, any EventLoop) async throws -> any Channel)?
    ) {
        self.configuration = configuration
        self.mode = if let customHandler { .custom(customHandler) } else { .default }
    }

    func makeConnection(
        address: STOMPServerAddress,
        connectionID: Int,
        eventLoop: any EventLoop,
        logger: Logger
    ) async throws -> STOMPConnection {
        switch self.mode {
        case .default:
            let connectionConfig = try await self.makeConnectionConfiguration()
            return try await STOMPConnection.connect(
                address: address,
                connectionID: connectionID,
                configuration: connectionConfig,
                eventLoop: eventLoop,
                logger: logger
            )

        case .custom(let customHandler):
            async let connectionConfigPromise = self.makeConnectionConfiguration()
            let channel = try await customHandler(address, eventLoop)
            let connectionConfig = try await connectionConfigPromise

            let connection = try await eventLoop.submit {
                let channelHandler = try STOMPConnection._setupChannel(
                    channel,
                    configuration: connectionConfig,
                    logger: logger
                )
                return STOMPConnection(
                    channel: channel,
                    connectionID: connectionID,
                    channelHandler: channelHandler,
                    configuration: connectionConfig,
                    logger: logger
                )
            }.get()
            try await connection.waitOnConnected()
            return connection
        }
    }

    func makeConnectionConfiguration() async throws -> STOMPConnectionConfiguration {
        let tls: STOMPConnectionConfiguration.TLS =
            switch self.configuration.tls.base {
            case .disable:
                .disable
            case .enable(let config, let clientName):
                switch config {
                #if os(macOS) || os(Linux) || os(Android)
                case .niossl(let niosslConfig):
                    .enable(.niossl(niosslConfig), tlsServerName: clientName)
                #endif
                #if canImport(Network)
                case .ts(let nwConfig):
                    .enable(.ts(nwConfig), tlsServerName: clientName)
                #endif
                }
            }

        return STOMPConnectionConfiguration(
            authentication: self.configuration.authentication.flatMap {
                .init(login: $0.login, passcode: $0.passcode)
            },
            virtualHost: self.configuration.virtualHost,
            heartBeat: (outgoing: self.configuration.heartBeat.outgoing, incoming: self.configuration.heartBeat.incoming),
            connectTimeout: self.configuration.connectTimeout,
            receiptTimeout: self.configuration.receiptTimeout,
            tls: tls,
            connectHeaders: self.configuration.connectHeaders,
            webSocket: self.configuration.webSocket.flatMap {
                .init(urlPath: $0.urlPath, maxFrameSize: $0.maxFrameSize)
            }
        )
    }
}
