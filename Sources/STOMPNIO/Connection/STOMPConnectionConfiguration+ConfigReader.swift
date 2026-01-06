public import Configuration
import NIOHTTP1

extension STOMPConnectionConfiguration {
    /// Creates a new STOMP connection configuration using values from the provided reader.
    ///
    /// ## Configuration keys
    /// - `stomp.auth.login` (string, optional): The user identifier used to authenticate against a secured STOMP server.
    /// - `stomp.auth.passcode` (string, optional): The password used to authenticate against a secured STOMP server.
    /// - `stomp.virtualHost` (string, optional): The name of a virtual host that the client wishes to connect to.
    /// - `stomp.heartBeat.outgoing` (int, optional): The smallest number of milliseconds between heart-beats that the client can guarantee to send.
    /// - `stomp.heartBeat.incoming` (int, optional): The desired number of milliseconds between heart-beats that the client would like to receive.
    /// - `stomp.connectTimeout` (int, optional, default: `10`): Maximum time to wait for the `CONNECTED` frame, in seconds.
    /// - `stomp.receiptTimeout` (int, optional, default: `30`): Maximum time to wait for a `RECEIPT` frame, in seconds.
    /// - `stomp.connectHeaders` (string array, optional): Additional user defined headers to include in the `CONNECT` frame, in the `<key>:<value>` format.
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
                    maxFrameSize: maxFrameSize ?? 1 << 24,
                    initialRequestHeaders: initialRequestHeaders ?? [:]
                )
            } else {
                nil
            }

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

extension HTTPHeaders {
    /// Creates HTTP headers from an array of configuration strings.
    ///
    /// Each configuration string must be in the `<key>:<value>` format.
    ///
    /// - Parameter configStringArray: The array of configuration strings to create the HTTP headers from.
    fileprivate init?(configStringArray: [String]) {
        var headers = HTTPHeaders()
        for configString in configStringArray {
            guard let colonIndex = configString.firstIndex(of: ":") else {
                return nil
            }
            let name = String(configString[..<colonIndex].trimmingWhitespace())
            let valueStartIndex = configString.index(after: colonIndex)
            let value = String(configString[valueStartIndex...].trimmingWhitespace())
            headers.add(name: name, value: value)
        }
        self = headers
    }
}
