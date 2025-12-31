public import NIOCore

/// A STOMP frame.
public struct STOMPFrame: Sendable, Equatable {
    /// The command string of the frame.
    public var command: STOMPCommand
    /// The headers of the frame.
    public var headers: STOMPHeaders
    /// Body bytes up to (but not including) `NULL` terminator.
    public var body: ByteBuffer

    /// Create a STOMP frame.
    ///
    /// - Parameters:
    ///   - command: The command of the frame.
    ///   - headers: The headers of the frame.
    ///   - body: Body bytes.
    public init(command: STOMPCommand, headers: STOMPHeaders, body: ByteBuffer = ByteBuffer()) {
        self.command = command
        self.headers = headers
        self.body = body
    }

    /// Create a STOMP frame.
    ///
    /// - Parameters:
    ///   - command: The command of the frame.
    ///   - headers: The headers of the frame.
    ///   - body: Body bytes.
    public init(command: STOMPCommand, headers: [STOMPHeader], body: ByteBuffer = ByteBuffer()) {
        self.command = command
        self.headers = STOMPHeaders(headers: headers)
        self.body = body
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
