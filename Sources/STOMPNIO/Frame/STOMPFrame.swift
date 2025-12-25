public import NIOCore

/// A STOMP frame
public struct STOMPFrame: Sendable, Equatable {
    /// The command string of the frame
    public let command: STOMPCommand
    /// The headers of the frame
    public let headers: [STOMPHeader]
    /// Body bytes up to (but not including) `NULL` terminator
    public var body: ByteBuffer

    public init(command: STOMPCommand, headers: [STOMPHeader], body: ByteBuffer = ByteBuffer()) {
        self.command = command
        self.headers = headers
        self.body = body
    }
}

/// A STOMP header
public struct STOMPHeader: Sendable, Equatable {
    /// The key of the header
    public let name: String
    /// The value of the header
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

extension STOMPFrame {
    func encode(into buffer: inout ByteBuffer) {
        // Write command
        buffer.writeString(self.command.rawValue)
        buffer.writeString("\n")

        // Write headers
        for header in self.headers {
            buffer.writeString("\(header.name):\(header.value)\n")
        }
        buffer.writeString("\n")  // End of headers

        // Write body
        var copy = self.body
        buffer.writeBuffer(&copy)

        // Write NULL terminator
        buffer.writeInteger(UInt8(0))
    }
}
