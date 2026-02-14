public import Configuration
import NIOHTTP1

extension STOMPClientConfiguration {
    /// Creates a new STOMP client configuration using values from the provided reader.
    ///
    /// ## Configuration keys
    /// - `stomp.auth.login` (string, optional): The user identifier used to authenticate against a secured STOMP server.
    /// - `stomp.auth.passcode` (string, optional): The password used to authenticate against a secured STOMP server.
    /// - `stomp.connectionPool.minimumConnectionCount` (int, optional, default: `0`): The minimum number of connections to maintain.
    /// - `stomp.connectionPool.maximumConnectionSoftLimit` (int, optional, default: `20`): The maximum number of connections to allow that are not closed immediately.
    /// - `stomp.connectionPool.maximumConnectionHardLimit` (int, optional, default: `20`): The maximum number of connections to allow.
    /// - `stomp.connectionPool.idleTimeout` (int, optional, default: `60`): The duration in seconds to allow a connect to be idle.
    /// - `stomp.connectionPool.circuitBreakerTripAfter` (int, optional, default: `60`): Time in seconds after first connection fail before circuit breaker trips.
    /// - `stomp.connectionPool.maximumConcurrentConnectionRequests` (int, optional, default: `20`): Maximum concurrent connection requests that can be run at one time.
    /// - `stomp.virtualHost` (string, optional): The name of a virtual host that the client wishes to connect to.
    /// - `stomp.heartBeat.outgoing` (int, optional): The smallest number of milliseconds between heart-beats that the client can guarantee to send.
    /// - `stomp.heartBeat.incoming` (int, optional): The desired number of milliseconds between heart-beats that the client would like to receive.
    /// - `stomp.connectTimeout` (int, optional, default: `10`): Maximum time to wait for the `CONNECTED` frame, in seconds.
    /// - `stomp.receiptTimeout` (int, optional, default: `30`): Maximum time to wait for a `RECEIPT` frame, in seconds.
    /// - `stomp.connectHeaders` (string array, optional): Additional user defined headers to include in the `CONNECT` frame, in the `<key>:<value>` format.
    /// - `stomp.webSocket.urlPath` (string, optional): The URL path to use when establishing the WebSocket connection.
    /// - `stomp.webSocket.maxFrameSize` (int, optional): The maximum frame size for the WebSocket connection.
    /// - `stomp.webSocket.initialRequestHeaders` (string array, optional): Initial HTTP headers to include in the WebSocket handshake request.
    ///
    /// > Note: TLS configuration is not read from the `ConfigReader` and is disabled by default. You must set the `tls` property manually after initialization.
    ///
    /// - Parameter config: The config reader to read configuration values from.
    public init(config: ConfigReader) {
        let stompConfig = config.scoped(to: "stomp")
        self.virtualHost = stompConfig.string(forKey: "virtualHost")
        self.connectTimeout = .seconds(stompConfig.int(forKey: "connectTimeout", default: 10))
        self.receiptTimeout = .seconds(stompConfig.int(forKey: "receiptTimeout", default: 30))

        let stompAuthConfig = stompConfig.scoped(to: "auth")
        let login = stompAuthConfig.string(forKey: "login")
        let passcode = stompAuthConfig.string(forKey: "passcode", isSecret: true)
        self.authentication =
            if let login, let passcode {
                .init(login: login, passcode: passcode)
            } else {
                nil
            }

        let stompConnectionPoolConfig = stompConfig.scoped(to: "connectionPool")
        self.connectionPool = .init(config: stompConnectionPoolConfig)

        let stompHeartBeatConfig = stompConfig.scoped(to: "heartBeat")
        let outgoing = stompHeartBeatConfig.int(forKey: "outgoing")
        let incoming = stompHeartBeatConfig.int(forKey: "incoming")
        self.heartBeat =
            if let outgoing, let incoming {
                (outgoing: .milliseconds(outgoing), incoming: .milliseconds(incoming))
            } else {
                (outgoing: .milliseconds(0), incoming: .milliseconds(0))
            }

        let connectHeaders = stompConfig.stringArray(forKey: "connectHeaders", as: STOMPHeader.self)
        self.connectHeaders =
            if let connectHeaders {
                STOMPHeaders(headers: connectHeaders)
            } else {
                [:]
            }

        let stompWebSocketConfig = stompConfig.scoped(to: "webSocket")
        let urlPath = stompWebSocketConfig.string(forKey: "urlPath")
        let maxFrameSize = stompWebSocketConfig.int(forKey: "maxFrameSize")
        let initialRequestHeaders = stompWebSocketConfig.stringArray(forKey: "initialRequestHeaders").flatMap {
            HTTPHeaders(configStringArray: $0)
        }
        self.webSocket =
            if urlPath != nil || maxFrameSize != nil || initialRequestHeaders != nil {
                .init(
                    urlPath: urlPath ?? "/ws",
                    maxFrameSize: maxFrameSize ?? 1 << 14,
                    initialRequestHeaders: initialRequestHeaders ?? [:]
                )
            } else {
                nil
            }

        // TLS is disabled by default
        self.tls = .disable
    }
}

extension STOMPClientConfiguration.ConnectionPool {
    fileprivate init(config: ConfigReader) {
        self.init(
            minimumConnectionCount: config.int(forKey: "minimumConnectionCount", default: 0),
            maximumConnectionSoftLimit: config.int(forKey: "maximumConnectionSoftLimit", default: 20),
            maximumConnectionHardLimit: config.int(forKey: "maximumConnectionHardLimit", default: 20),
            idleTimeout: .seconds(config.int(forKey: "idleTimeout", default: 60)),
            circuitBreakerTripAfter: .seconds(config.int(forKey: "circuitBreakerTripAfter", default: 60)),
            maximumConcurrentConnectionRequests: config.int(forKey: "maximumConcurrentConnectionRequests", default: 20)
        )
    }
}
