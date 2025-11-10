/// A STOMP command
public enum STOMPCommand: String, Sendable, CaseIterable {
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
}
