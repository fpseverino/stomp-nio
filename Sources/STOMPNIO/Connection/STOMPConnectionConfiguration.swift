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

    /// Creates a new STOMP connection configuration.
    ///
    /// Use this initializer to create a configuration object
    /// that can be used to establish a connection to a STOMP server with the specified parameters.
    ///
    /// - Parameters:
    ///   - authentication: Optional credentials for accessing the STOMP server. Set to `nil` for unauthenticated access.
    ///   - virtualHost: The name of a virtual host that the client wishes to connect to.
    ///   - connectTimeout: Maximum time to wait for the CONNECTED frame. Defaults to 10 seconds.
    ///   - receiptTimeout: Maximum time to wait for a RECEIPT frame. Defaults to 30 seconds.
    public init(
        authentication: Authentication? = nil,
        virtualHost: String? = nil,
        connectTimeout: Duration = .seconds(10),
        receiptTimeout: Duration = .seconds(30)
    ) {
        self.authentication = authentication
        self.virtualHost = virtualHost
        self.connectTimeout = connectTimeout
        self.receiptTimeout = receiptTimeout
    }
}
