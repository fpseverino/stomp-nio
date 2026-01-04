/// A configuration object that defines how to connect to a STOMP server.
public struct STOMPConnectionConfiguration: Sendable {
    /// Authentication credentials for accessing a STOMP server.
    ///
    /// Use this structure to provide user ID and password credentials
    /// when the server requires authentication for access.
    public struct Authentication: Sendable {
        /// The user identifier used to authenticate against a secured STOMP server.
        public var login: String
        /// The password used to authenticate against a secured STOMP server.
        public var passcode: String

        /// Creates a new authentication configuration.
        ///
        /// - Parameters:
        ///   - login: The user identifier used to authenticate against a secured STOMP server.
        ///   - passcode: The password used to authenticate against a secured STOMP server.
        public init(login: String, passcode: String) {
            self.login = login
            self.passcode = passcode
        }
    }

    /// Optional authentication credentials for accessing the STOMP server.
    ///
    /// Set this property when connecting to a server that requires authentication.
    public var authentication: Authentication?

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

    /// Creates a new STOMP connection configuration.
    ///
    /// Use this initializer to create a configuration object
    /// that can be used to establish a connection to a STOMP server with the specified parameters.
    ///
    /// - Parameters:
    ///   - authentication: Optional credentials for accessing the STOMP server. Set to `nil` for unauthenticated access.
    ///   - virtualHost: The name of a virtual host that the client wishes to connect to.
    ///   - heartBeat: The heart-beating configuration for the STOMP connection. Defaults to no heart-beating.
    ///   - connectTimeout: Maximum time to wait for the `CONNECTED` frame. Defaults to 10 seconds.
    ///   - receiptTimeout: Maximum time to wait for a `RECEIPT` frame. Defaults to 30 seconds.
    ///   - connectHeaders: Additional user defined headers to include in the `CONNECT` frame.
    public init(
        authentication: Authentication? = nil,
        virtualHost: String? = nil,
        heartBeat: (outgoing: Duration, incoming: Duration) = (outgoing: .milliseconds(0), incoming: .milliseconds(0)),
        connectTimeout: Duration = .seconds(10),
        receiptTimeout: Duration = .seconds(30),
        connectHeaders: STOMPHeaders = [:]
    ) {
        self.authentication = authentication
        self.virtualHost = virtualHost
        self.heartBeat = heartBeat
        self.connectTimeout = connectTimeout
        self.receiptTimeout = receiptTimeout
        self.connectHeaders = connectHeaders
    }
}
