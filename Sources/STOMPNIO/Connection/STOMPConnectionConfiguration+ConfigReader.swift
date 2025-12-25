public import Configuration

extension STOMPConnectionConfiguration {
    /// Creates a new STOMP connection configuration using values from the provided reader.
    ///
    /// ## Configuration keys
    /// - `stomp.auth.login` (string, optional): The user identifier used to authenticate against a secured STOMP server.
    /// - `stomp.auth.passcode` (string, optional): The password used to authenticate against a secured STOMP server.
    /// - `stomp.virtualHost` (string, optional): The name of a virtual host that the client wishes to connect to.
    /// - `stomp.connectTimeout` (int, optional, default: `10`): Maximum time to wait for the CONNECTED frame, in seconds.
    /// - `stomp.receiptTimeout` (int, optional, default: `30`): Maximum time to wait for a RECEIPT frame, in seconds.
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
    }
}
