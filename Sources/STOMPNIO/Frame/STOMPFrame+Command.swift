extension STOMPFrame {
    /// A STOMP command.
    public enum Command: String, Sendable, Hashable, CaseIterable, LosslessStringConvertible {
        // Client commands
        case connect = "CONNECT"
        case stomp = "STOMP"
        case send = "SEND"
        case subscribe = "SUBSCRIBE"
        case unsubscribe = "UNSUBSCRIBE"
        case begin = "BEGIN"
        case commit = "COMMIT"
        case abort = "ABORT"
        case ack = "ACK"
        case nack = "NACK"
        case disconnect = "DISCONNECT"

        // Server commands
        case connected = "CONNECTED"
        case message = "MESSAGE"
        case receipt = "RECEIPT"
        case error = "ERROR"

        /// Create a STOMP command from a string.
        /// Returns `nil` if the string does not correspond to a valid command.
        ///
        /// - Parameter command: The command string.
        public init?(_ command: String) {
            self.init(rawValue: command)
        }

        /// A textual representation of the command.
        public var description: String {
            return self.rawValue
        }
    }
}
