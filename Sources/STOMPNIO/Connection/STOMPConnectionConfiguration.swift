public import HTTPTypes

#if os(macOS) || os(Linux) || os(Android)
public import NIOSSL
#endif

/// A configuration object that defines how to connect to a STOMP server.
///
/// ``STOMPConnectionConfiguration`` allows you to customize various aspects of the connection,
/// including authentication credentials, timeouts, and TLS security settings.
///
/// Example usage:
/// ```swift
/// // Basic configuration
/// let config = STOMPConnectionConfiguration()
///
/// // Configuration with authentication
/// let authConfig = STOMPConnectionConfiguration(
///     authentication: .init(login: "user", passcode: "pass"),
///     receiptTimeout: .seconds(60)
/// )
///
/// // Configuration with TLS
/// let tlsConfig = TLSConfiguration.makeClientConfiguration()
/// let secureConfig = STOMPConnectionConfiguration(
///     authentication: .init(login: "user", passcode: "pass"),
///     tls: .enable(.niossl(tlsConfig), tlsServerName: "your-stomp-broker.com")
/// )
/// ```
public struct STOMPConnectionConfiguration: Sendable {
    /// Configuration for TLS (Transport Layer Security) encryption.
    ///
    /// This structure allows you to enable or disable encrypted connections to the STOMP broker.
    /// When enabled, it requires a ``STOMPConnectionConfiguration/TLS/Configuration``
    /// and optionally a server name for SNI (Server Name Indication).
    public struct TLS: Sendable {
        /// Enum for different TLS Configuration types.
        ///
        /// The TLS Configuration type to use is defined by the `EventLoopGroup` the client is using.
        /// If you don't provide an `EventLoopGroup` then the `EventLoopGroup` created will be defined by this variable.
        /// It is recommended on iOS that you use NIO Transport Services.
        public enum Configuration: Sendable {
            /// NIOSSL TLS configuration.
            #if os(macOS) || os(Linux) || os(Android)
            case niossl(TLSConfiguration)
            #endif
            #if canImport(Network)
            /// NIO Transport Services TLS configuration.
            case ts(TSTLSConfiguration)
            #endif
        }
        enum Base {
            case disable
            case enable(Configuration, tlsServerName: String?)
        }
        let base: Base

        /// Disables TLS for the connection.
        ///
        /// Use this option when connecting to a STOMP broker that doesn't require encryption.
        public static var disable: Self { .init(base: .disable) }

        /// Enables TLS for the connection.
        ///
        /// - Parameters:
        ///   - configuration: The TLS configuration used to establish the secure connection
        ///   - tlsServerName: Optional server name for SNI (Server Name Indication)
        /// - Returns: A configured TLS instance
        public static func enable(_ configuration: Configuration, tlsServerName: String?) -> Self {
            .init(base: .enable(configuration, tlsServerName: tlsServerName))
        }
    }

    /// WebSocket configuration for the STOMP connection.
    public struct WebSocket: Sendable {
        /// WebSocket URL.
        public var urlPath: String
        /// The maximum frame size the WebSocket client will allow.
        public var maxFrameSize: Int
        /// Additional headers to add to the initial HTTP request.
        public var initialRequestHeaders: HTTPFields

        /// Creates a new WebSocket configuration.
        ///
        /// - Parameters:
        ///   - urlPath: WebSocket URL, defaults to "/ws".
        ///   - maxFrameSize: The maximum frame size the WebSocket client will allow.
        ///   - initialRequestHeaders: Additional headers to add to the initial HTTP request.
        public init(
            urlPath: String = "/ws",
            maxFrameSize: Int = 1 << 14,
            initialRequestHeaders: HTTPFields = [:]
        ) {
            self.urlPath = urlPath
            self.maxFrameSize = maxFrameSize
            self.initialRequestHeaders = initialRequestHeaders
        }
    }

    /// The user identifier used to authenticate against a secured STOMP server.
    public var login: String?

    /// The password used to authenticate against a secured STOMP server.
    public var passcode: String?

    /// TLS configuration for the connection.
    ///
    /// Use `.disable` for unencrypted connections or `.enable(...)` for secure connections.
    public var tls: TLS

    /// The name of a virtual host that the client wishes to connect to.
    ///
    /// It is recommended clients set this to the host name that the socket was established against, or to any name of their choosing.
    ///
    /// If this header does not match a known virtual host,
    /// servers supporting virtual hosting MAY select a default virtual host or reject the connection.
    ///
    /// > Note: If not set, no "host" header will be sent in the CONNECT frame.
    public var virtualHost: String?

    /// The heart-beating configuration for the STOMP connection.
    ///
    /// The first `Duration` represents what the sender of the frame can do (outgoing heart-beats):
    /// - 0 means it cannot send heart-beats
    /// - otherwise it is the smallest amount of time between heart-beats that it can guarantee
    ///
    /// The second `Duration` represents what the sender of the frame would like to get (incoming heart-beats):
    /// - 0 means it does not want to receive heart-beats
    /// - otherwise it is the desired amount of time between heart-beats
    public var heartBeat: (outgoing: Duration, incoming: Duration)

    /// The maximum time to wait for the CONNECTED frame after sending the CONNECT frame.
    ///
    /// If the timeout is reached without receiving a CONNECTED frame,
    /// the connection attempt will fail with a timeout error.
    ///
    /// Default value is 10 seconds.
    public var connectTimeout: Duration

    /// The maximum time to wait for a RECEIPT frame before considering the connection dead.
    ///
    /// This timeout applies to all frames with a receipt header sent to the STOMP broker.
    ///
    /// Default value is 30 seconds.
    public var receiptTimeout: Duration

    /// Additional user defined headers to include in the `CONNECT` frame.
    public var connectHeaders: STOMPHeaders

    /// WebSocket configuration for the STOMP connection.
    public var webSocket: WebSocket?

    /// Creates a new STOMP connection configuration.
    ///
    /// Use this initializer to create a configuration object
    /// that can be used to establish a connection to a STOMP server with the specified parameters.
    ///
    /// - Parameters:
    ///   - login: Optional user identifier for accessing the STOMP server. Set to `nil` for unauthenticated access.
    ///   - passcode: Optional password for accessing the STOMP server. Set to `nil` for unauthenticated access.
    ///   - virtualHost: The name of a virtual host that the client wishes to connect to.
    ///   - heartBeat: The heart-beating configuration for the STOMP connection. Defaults to no heart-beating.
    ///   - connectTimeout: Maximum time to wait for the `CONNECTED` frame. Defaults to 10 seconds.
    ///   - receiptTimeout: Maximum time to wait for a `RECEIPT` frame. Defaults to 30 seconds.
    ///   - tls: TLS configuration for secure connections. Defaults to `.disable` for unencrypted connections.
    ///   - connectHeaders: Additional user defined headers to include in the `CONNECT` frame.
    ///   - webSocket: WebSocket configuration for the STOMP connection. Defaults to `nil` for non-WebSocket connections.
    public init(
        login: String? = nil,
        passcode: String? = nil,
        virtualHost: String? = nil,
        heartBeat: (outgoing: Duration, incoming: Duration) = (outgoing: .milliseconds(0), incoming: .milliseconds(0)),
        connectTimeout: Duration = .seconds(10),
        receiptTimeout: Duration = .seconds(30),
        tls: TLS = .disable,
        connectHeaders: STOMPHeaders = [:],
        webSocket: WebSocket? = nil
    ) {
        self.login = login
        self.passcode = passcode
        self.virtualHost = virtualHost
        self.heartBeat = heartBeat
        self.connectTimeout = connectTimeout
        self.receiptTimeout = receiptTimeout
        self.tls = tls
        self.connectHeaders = connectHeaders
        self.webSocket = webSocket
    }
}
