public import Configuration
import HTTPTypes

extension STOMPConnectionConfiguration {
    /// Creates a new STOMP connection configuration using values from the provided reader.
    ///
    /// ## Configuration keys
    /// - `login` (string, optional): The user identifier used to authenticate against a secured STOMP server.
    /// - `passcode` (string, optional): The password used to authenticate against a secured STOMP server.
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

extension STOMPHeader: ExpressibleByConfigString {
    /// Creates a STOMP header from a configuration string.
    ///
    /// The configuration string must be in the `<key>:<value>` format.
    ///
    /// - Parameter configString: The configuration string to create the STOMP header from.
    public init?(configString: String) {
        guard let colonIndex = configString.firstIndex(of: ":") else {
            return nil
        }
        let name = STOMPHeader.Name(String(configString[..<colonIndex]))
        let valueStartIndex = configString.index(after: colonIndex)
        let value = String(configString[valueStartIndex...])
        self.init(name: name, value: value)
    }
}

struct ConfigHTTPField: ExpressibleByConfigString {
    let name: HTTPField.Name
    let value: String

    init(name: HTTPField.Name, value: String) {
        self.name = name
        self.value = value
    }

    /// Creates a HTTP header from a configuration string.
    ///
    /// The configuration string must be in the `<key>:<value>` format.
    ///
    /// - Parameter configString: The configuration string to create the HTTP header from.
    init?(configString: String) {
        guard let colonIndex = configString.firstIndex(of: ":") else {
            return nil
        }
        guard let name = HTTPField.Name(String(configString[..<colonIndex].trimmingWhitespace())) else {
            return nil
        }
        let valueStartIndex = configString.index(after: colonIndex)
        let value = String(configString[valueStartIndex...].trimmingWhitespace())
        self.init(name: name, value: value)
    }

    var description: String { "\(name):\(value)" }
}

extension STOMPConnectionConfiguration.WebSocket {
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
