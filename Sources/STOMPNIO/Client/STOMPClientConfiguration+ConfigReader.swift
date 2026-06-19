public import Configuration
import HTTPTypes

extension STOMPClientConfiguration {
    /// Creates a new STOMP client configuration using values from the provided reader.
    ///
    /// ## Configuration keys
    /// - `login` (string, optional): The user identifier used to authenticate against a secured STOMP server.
    /// - `passcode` (string, optional): The password used to authenticate against a secured STOMP server.
    /// - `connectionPool.minimumConnectionCount` (int, optional, default: `0`): The minimum number of connections to maintain.
    /// - `connectionPool.maximumConnectionSoftLimit` (int, optional, default: `20`): The maximum number of connections to allow that are not closed immediately.
    /// - `connectionPool.maximumConnectionHardLimit` (int, optional, default: `20`): The maximum number of connections to allow.
    /// - `connectionPool.idleTimeout` (int, optional, default: `60`): The duration in seconds to allow a connect to be idle.
    /// - `connectionPool.circuitBreakerTripAfter` (int, optional, default: `60`): Time in seconds after first connection fail before circuit breaker trips.
    /// - `connectionPool.maximumConcurrentConnectionRequests` (int, optional, default: `20`): Maximum concurrent connection requests that can be run at one time.
    /// - `virtualHost` (string, optional): The name of a virtual host that the client wishes to connect to.
    /// - `heartBeat.outgoing` (int, optional): The smallest number of milliseconds between heart-beats that the client can guarantee to send.
    /// - `heartBeat.incoming` (int, optional): The desired number of milliseconds between heart-beats that the client would like to receive.
    /// - `connectTimeout` (int, optional, default: `10`): Maximum time to wait for the `CONNECTED` frame, in seconds.
    /// - `receiptTimeout` (int, optional, default: `30`): Maximum time to wait for a `RECEIPT` frame, in seconds.
    /// - `connectHeaders` (string array, optional): Additional user defined headers to include in the `CONNECT` frame, in the `<key>:<value>` format.
    /// - `webSocket.urlPath` (string, optional): The URL path to use when establishing the WebSocket connection.
    /// - `webSocket.maxFrameSize` (int, optional): The maximum frame size for the WebSocket connection.
    /// - `webSocket.initialRequestHeaders` (string array, optional): Initial HTTP headers to include in the WebSocket handshake request.
    ///
    /// > Note: TLS configuration is not read from the `ConfigReader` and is disabled by default. You must set the `tls` property manually after initialization.
    ///
    /// - Parameter config: The config reader to read configuration values from.
    public init(config: ConfigReader) {
        self.virtualHost = config.string(forKey: "virtualHost")
        self.connectTimeout = .seconds(config.int(forKey: "connectTimeout", default: 10))
        self.receiptTimeout = .seconds(config.int(forKey: "receiptTimeout", default: 30))
        self.login = config.string(forKey: "login")
        self.passcode = config.string(forKey: "passcode", isSecret: true)

        let stompConnectionPoolConfig = config.scoped(to: "connectionPool")
        self.connectionPool = .init(config: stompConnectionPoolConfig)

        let stompHeartBeatConfig = config.scoped(to: "heartBeat")
        let outgoing = stompHeartBeatConfig.int(forKey: "outgoing")
        let incoming = stompHeartBeatConfig.int(forKey: "incoming")
        self.heartBeat =
            if let outgoing, let incoming {
                (outgoing: .milliseconds(outgoing), incoming: .milliseconds(incoming))
            } else {
                (outgoing: .milliseconds(0), incoming: .milliseconds(0))
            }

        let connectHeaders = config.stringArray(forKey: "connectHeaders", as: STOMPHeader.self)
        self.connectHeaders =
            if let connectHeaders {
                STOMPHeaders(headers: connectHeaders)
            } else {
                [:]
            }

        self.webSocket = .init(config: config)

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

extension STOMPClientConfiguration.WebSocket {
    /// Creates a new WebSocket configuration using values from the provided reader.
    ///
    /// ## Configuration keys
    /// - `webSocket.urlPath` (string, optional): The URL path to use when establishing the WebSocket connection.
    /// - `webSocket.maxFrameSize` (int, optional): The maximum frame size for the WebSocket connection.
    /// - `webSocket.initialRequestHeaders` (string array, optional): Initial HTTP headers to include in the WebSocket handshake request.
    ///
    /// - Parameter config: The config reader to read configuration values from.
    init?(config: ConfigReader) {
        let webSocketConfig = config.scoped(to: "webSocket")
        let urlPath = webSocketConfig.string(forKey: "urlPath")
        let maxFrameSize = webSocketConfig.int(forKey: "maxFrameSize")
        let initialRequestHeaders: HTTPFields?
        if let initialRequestHeadersArray = webSocketConfig.stringArray(forKey: "initialRequestHeaders", as: ConfigHTTPField.self) {
            var headers = HTTPFields()
            for header in initialRequestHeadersArray {
                headers.append(.init(name: header.name, value: header.value))
            }
            initialRequestHeaders = headers
        } else {
            initialRequestHeaders = nil
        }

        if urlPath != nil || maxFrameSize != nil || initialRequestHeaders != nil {
            self.init(
                urlPath: urlPath ?? "/ws",
                maxFrameSize: maxFrameSize ?? 1 << 14,
                initialRequestHeaders: initialRequestHeaders ?? [:]
            )
        } else {
            return nil
        }
    }
}
