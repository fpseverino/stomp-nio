public import HTTPTypes
import _STOMPConnectionPool

#if os(macOS) || os(Linux) || os(Android)
public import NIOSSL
#endif

/// Configuration for the ``STOMPClient``.
public struct STOMPClientConfiguration: Sendable {
    /// Configuration for TLS (Transport Layer Security) encryption.
    ///
    /// This structure allows you to enable or disable encrypted connections to the STOMP broker.
    /// When enabled, it requires a ``STOMPClientConfiguration/TLS/Configuration``
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
            case enable(Configuration, String?)
        }
        let base: Base

        /// Disables TLS for the client.
        ///
        /// Use this option when connecting to a STOMP broker that doesn't require encryption.
        public static var disable: Self { .init(base: .disable) }

        /// Enables TLS for the client.
        ///
        /// - Parameters:
        ///   - configuration: The TLS configuration used to establish secure connections
        ///   - tlsServerName: Optional server name for SNI (Server Name Indication)
        /// - Returns: A configured TLS instance
        public static func enable(_ configuration: Configuration, tlsServerName: String?) -> Self {
            .init(base: .enable(configuration, tlsServerName))
        }
    }

    /// WebSocket configuration for the STOMP client.
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

    /// The connection pool definition for STOMP connections.
    public struct ConnectionPool: Hashable, Sendable {
        /// The minimum number of connections to preserve in the pool.
        ///
        /// If the pool is mostly idle and the remote servers closes
        /// idle connections,  the ``STOMPClient`` will initiate new outbound
        /// connections proactively to avoid the number of available
        /// connections dropping below this number.
        public var minimumConnectionCount: Int

        /// Between the ``STOMPClientConfiguration/ConnectionPool/minimumConnectionCount`` and
        /// `maximumConnectionSoftLimit` the connection pool creates _preserved_ connections.
        /// Preserved connections are closed if they have been idle for ``STOMPClientConfiguration/ConnectionPool/idleTimeout``.
        public var maximumConnectionSoftLimit: Int

        /// The maximum number of connections for this pool, that can exist at any point in time.
        /// The pool can create _overflow_ connections, if all connections are leased,
        /// and the `maximumConnectionHardLimit` > ``STOMPClientConfiguration/ConnectionPool/maximumConnectionSoftLimit``.
        /// Overflow connections are closed immediately as soon as they become idle.
        public var maximumConnectionHardLimit: Int

        /// The time that a _preserved_ idle connection stays in the pool before it is closed.
        public var idleTimeout: Duration

        /// The amount of time to pass between the first failed connection before triggering the circuit breaker.
        public var circuitBreakerTripAfter: Duration

        /// Maximum number of in-progress new connection requests to run at any one time.
        public var maximumConcurrentConnectionRequests: Int

        /// Creates the configuration for a STOMP client connection pool.
        ///
        /// - Parameters:
        ///   - minimumConnectionCount: The minimum number of connections to maintain.
        ///   - maximumConnectionSoftLimit: The maximum number of connections to allow that are not closed immediately.
        ///   - maximumConnectionHardLimit: The maximum number of connections to allow.
        ///   - idleTimeout: The duration to allow a connect to be idle, that defaults to 60 seconds.
        ///   - circuitBreakerTripAfter: Time after first connection fail before circuit breaker trips.
        ///   - maximumConcurrentConnectionRequests: Maximum concurrent connection requests that can be run at one time.
        public init(
            minimumConnectionCount: Int = 0,
            maximumConnectionSoftLimit: Int = 20,
            maximumConnectionHardLimit: Int = 20,
            idleTimeout: Duration = .seconds(60),
            circuitBreakerTripAfter: Duration = .seconds(60),
            maximumConcurrentConnectionRequests: Int = 20
        ) {
            precondition(
                minimumConnectionCount <= maximumConnectionSoftLimit,
                "Minimum connection count cannot be greater than maximum connection soft limit"
            )
            precondition(
                maximumConnectionSoftLimit <= maximumConnectionHardLimit,
                "Maximum connection soft limit connection count cannot be greater than the maximum connection hard limit"
            )
            self.minimumConnectionCount = minimumConnectionCount
            self.maximumConnectionSoftLimit = maximumConnectionSoftLimit
            self.maximumConnectionHardLimit = maximumConnectionHardLimit
            self.idleTimeout = idleTimeout
            self.circuitBreakerTripAfter = circuitBreakerTripAfter
            self.maximumConcurrentConnectionRequests = maximumConcurrentConnectionRequests
        }
    }

    /// The user identifier used to authenticate against a secured STOMP server.
    public var login: String?

    /// The password used to authenticate against a secured STOMP server.
    public var passcode: String?

    /// The connection pool configuration.
    public var connectionPool: ConnectionPool

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

    /// Additional user defined headers to include in the `CONNECT` frame.
    public var connectHeaders: STOMPHeaders

    /// WebSocket configuration for the STOMP connection.
    public var webSocket: WebSocket?

    /// Creates a STOMP client configuration.
    ///
    /// - Parameters:
    ///   - login: The user identifier used to authenticate against a secured STOMP server. Set to `nil` for unauthenticated access.
    ///   - passcode: The password used to authenticate against a secured STOMP server. Set to `nil` for unauthenticated access.
    ///   - connectionPool: The connection pool configuration, defaults to a new instance of ``STOMPClientConfiguration/ConnectionPool``.
    ///   - connectTimeout: The maximum time to wait for the CONNECTED frame after sending the CONNECT frame, defaults to 10 seconds.
    ///   - receiptTimeout: The maximum time to wait for a RECEIPT frame before considering the connection dead, defaults to 30 seconds.
    ///   - tls: TLS configuration for the connection, defaults to `.disable`.
    ///   - virtualHost: The name of a virtual host that the client wishes to connect to, defaults to `nil`.
    ///   - heartBeat: The heart-beating configuration for the STOMP connection, defaults to no heart-beats.
    ///   - connectHeaders: Additional user defined headers to include in the `CONNECT` frame, defaults to an empty dictionary.
    ///   - webSocket: WebSocket configuration for the STOMP connection, defaults to `nil`.
    public init(
        login: String? = nil,
        passcode: String? = nil,
        connectionPool: ConnectionPool = .init(),
        connectTimeout: Duration = .seconds(10),
        receiptTimeout: Duration = .seconds(30),
        tls: TLS = .disable,
        virtualHost: String? = nil,
        heartBeat: (outgoing: Duration, incoming: Duration) = (outgoing: .seconds(0), incoming: .seconds(0)),
        connectHeaders: STOMPHeaders = [:],
        webSocket: WebSocket? = nil
    ) {
        self.login = login
        self.passcode = passcode
        self.connectionPool = connectionPool
        self.connectTimeout = connectTimeout
        self.receiptTimeout = receiptTimeout
        self.tls = tls
        self.virtualHost = virtualHost
        self.heartBeat = heartBeat
        self.connectHeaders = connectHeaders
        self.webSocket = webSocket
    }
}
