public import Configuration
import HTTPTypes

#if os(macOS) || os(Linux) || os(Android)
import NIOSSL
#endif

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
    /// ### TLS configuration keys
    /// - `tls.serverName` (string, optional): Optional server name for SNI (Server Name Indication). Valid for both `NIOSSL` and `NIOTransportServices`.
    /// ### NIOTransportServices specific configuration keys (takes precedence over NIOSSL if available)
    /// - `tls.niots.serverName` (string, optional): Name alias for `tls.serverName`. If both `tls.serverName` and `tls.niots.serverName` are provided, the value from `tls.serverName` will be used.
    /// - `tls.niots.privateKey` (string): TLS private key as a file path to a `.p12` file for NIOTransportServices.
    /// - `tls.niots.privateKeyPassword` (string): Password for the TLS private key. Only applicable for NIOTransportServices.
    /// - `tls.niots.trustRoots` (string, optional): TLS trust roots as a file path to a `.der` file for NIOTransportServices.
    /// ### NIOSSL specific configuration keys (used as fallback)
    /// - `tls.certificateChain` (string): TLS certificate chain in PEM format. Only applicable for `NIOSSL`.
    /// - `tls.privateKey` (string): TLS private key, in PEM format for NIOSSL.
    /// - `tls.trustRoots` (string, optional): TLS trust roots, in PEM format for NIOSSL.
    /// ### WebSocket specific configuration keys
    /// - `webSocket.urlPath` (string, optional): The URL path to use when establishing the WebSocket connection.
    /// - `webSocket.maxFrameSize` (int, optional): The maximum frame size for the WebSocket connection.
    /// - `webSocket.initialRequestHeaders` (string array, optional): Initial HTTP headers to include in the WebSocket handshake request.
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

        self.tls = (try? .init(config: config.scoped(to: "tls"))) ?? .disable

        let connectHeaders = config.stringArray(forKey: "connectHeaders", as: STOMPHeader.self)
        self.connectHeaders =
            if let connectHeaders {
                STOMPHeaders(headers: connectHeaders)
            } else {
                [:]
            }

        self.webSocket = .init(config: config.scoped(to: "webSocket"))
    }
}

#if canImport(Network)
extension TSTLSConfiguration {
    /// Creates a new TLS configuration for NIO Transport Services using values from the provided reader.
    ///
    /// ## Configuration keys
    /// - `privateKey` (string): TLS private key, as a file path to a `.p12` file.
    /// - `privateKeyPassword` (string): Password for the TLS private key.
    /// - `trustRoots` (string): TLS trust roots, as a file path to a `.der` file.
    ///
    /// - Parameter config: The config reader to read configuration values from.
    init(config: ConfigReader) throws {
        try self.init(
            trustRoots: .der(config.requiredString(forKey: "trustRoots")),
            clientIdentity: .p12(
                filename: config.requiredString(forKey: "privateKey"),
                password: config.requiredString(forKey: "privateKeyPassword", isSecret: true)
            )
        )
    }
}
#endif

extension STOMPConnectionConfiguration.TLS {
    private enum _TLSConfigError: Error {
        case missingConfiguration
    }

    /// Creates a new TLS configuration using values from the provided reader.
    ///
    /// If the `niots` scoped configuration is present, and NIOTransportServices is available, it will be used as it takes precedence over the `NIOSSL` configuration.
    /// Otherwise, the `NIOSSL` configuration will be used.
    ///
    /// ## Configuration keys
    /// - `serverName` (string, optional): Optional server name for SNI (Server Name Indication). Valid for both `NIOSSL` and `NIOTransportServices`.
    /// ### NIOTransportServices specific configuration keys
    /// - `niots.serverName` (string, optional): Name alias for `serverName`. If both `serverName` and `niots.serverName` are provided, the value from `serverName` will be used.
    /// - `niots.privateKey` (string): TLS private key as a file path to a `.p12` file for NIOTransportServices.
    /// - `niots.privateKeyPassword` (string): Password for the TLS private key. Only applicable for NIOTransportServices.
    /// - `niots.trustRoots` (string, optional): TLS trust roots as a file path to a `.der` file for NIOTransportServices.
    /// ### NIOSSL specific configuration keys (used as fallback)
    /// - `certificateChain` (string): TLS certificate chain in PEM format. Only applicable for `NIOSSL`.
    /// - `privateKey` (string): TLS private key, in PEM format for NIOSSL.
    /// - `trustRoots` (string, optional): TLS trust roots, in PEM format for NIOSSL.
    ///
    /// - Parameter config: The config reader to read configuration values from.
    ///
    /// - Throws: An internal error type if no compatible TLS configuration is found in the provided reader.
    init(config: ConfigReader) throws {
        let tlsServerName = config.string(forKey: "serverName")
        #if canImport(Network)
        let nioTSConfigReader = config.scoped(to: "niots")
        if let tsTLSConfiguration = try? TSTLSConfiguration(config: nioTSConfigReader) {
            self.base = .enable(.ts(tsTLSConfiguration), tlsServerName: tlsServerName ?? nioTSConfigReader.string(forKey: "serverName"))
            return
        }
        #endif
        #if os(macOS) || os(Linux) || os(Android)
        let privateKey = try config.requiredString(forKey: "privateKey")
        let trustRoots = config.string(forKey: "trustRoots")
        let certificateChainPEM = try config.requiredString(forKey: "certificateChain")
        let certificateChain = try NIOSSLCertificate.fromPEMBytes([UInt8](certificateChainPEM.utf8))
        let nioSSLPrivateKey = try NIOSSLPrivateKey(bytes: [UInt8](privateKey.utf8), format: .pem)
        let nioSSLTrustRoots = try trustRoots.map { try NIOSSLCertificate.fromPEMBytes([UInt8]($0.utf8)) }
        var tlsConfiguration = TLSConfiguration.makeServerConfiguration(
            certificateChain: certificateChain.map { .certificate($0) },
            privateKey: .privateKey(nioSSLPrivateKey)
        )
        tlsConfiguration.trustRoots = nioSSLTrustRoots.map { .certificates($0) }
        self.base = .enable(.niossl(tlsConfiguration), tlsServerName: tlsServerName)
        return
        #else
        throw _TLSConfigError.missingConfiguration
        #endif
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
    let field: HTTPField

    init(field: HTTPField) {
        self.field = field
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
        self.init(field: HTTPField(name: name, value: value))
    }

    var description: String { "\(field.name):\(field.value)" }
}

extension STOMPConnectionConfiguration.WebSocket {
    /// Creates a new WebSocket configuration using values from the provided reader.
    ///
    /// ## Configuration keys
    /// - `urlPath` (string, optional): The URL path to use when establishing the WebSocket connection.
    /// - `maxFrameSize` (int, optional): The maximum frame size for the WebSocket connection.
    /// - `initialRequestHeaders` (string array, optional): Initial HTTP headers to include in the WebSocket handshake request.
    ///
    /// - Parameter config: The config reader to read configuration values from.
    init?(config: ConfigReader) {
        let urlPath = config.string(forKey: "urlPath")
        let maxFrameSize = config.int(forKey: "maxFrameSize")
        let initialRequestHeaders: HTTPFields? =
            if let initialRequestHeadersArray = config.stringArray(forKey: "initialRequestHeaders", as: ConfigHTTPField.self) {
                HTTPFields(initialRequestHeadersArray.lazy.map { $0.field })
            } else {
                nil
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
