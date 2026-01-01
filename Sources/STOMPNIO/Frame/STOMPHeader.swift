/// A STOMP header.
public struct STOMPHeader: Sendable, Hashable {
    /// The key of the header.
    public var name: Name
    /// The value of the header.
    public var value: String

    /// Create a STOMP header.
    ///
    /// - Parameters:
    ///   - name: The key of the header.
    ///   - value: The value of the header.
    public init(name: Name, value: String) {
        self.name = name
        self.value = value
    }

    /// Create a STOMP header.
    ///
    /// - Parameters:
    ///   - name: The key of the header.
    ///   - value: The value of the header.
    public init(name: String, value: String) {
        self.name = Name(name)
        self.value = value
    }
}

extension STOMPHeader: CustomStringConvertible {
    /// The header in the `<key>:<value>` format.
    public var description: String {
        "\(self.name):\(self.value)"
    }
}

extension STOMPHeader: CustomPlaygroundDisplayConvertible {
    /// The header in the `<key>:<value>` format.
    public var playgroundDescription: Any {
        self.description
    }
}

extension STOMPHeader {
    /// The name (or key) of a STOMP header.
    public struct Name: Sendable, Hashable {
        /// The string value of the header name.
        public let name: String

        /// Create a STOMP header name.
        ///
        /// - Parameter name: The string value of the header name.
        public init(_ name: String) {
            self.name = name
        }
    }
}

extension STOMPHeader.Name: LosslessStringConvertible {
    /// The string representation of the header name.
    public var description: String {
        self.name
    }
}

extension STOMPHeader.Name: CustomPlaygroundDisplayConvertible {
    /// The string representation of the header name.
    public var playgroundDescription: Any {
        self.description
    }
}

extension STOMPHeader.Name {
    /// This header is an octet count for the length of the message body.
    public static var contentLength: Self { "content-length" }
    /// If the `content-type` header is set, its value MUST be a MIME type which describes the format of the body.
    public static var contentType: Self { "content-type" }
    /// This will cause the server to acknowledge the processing of the client frame with a `RECEIPT` frame.
    public static var receipt: Self { "receipt" }

    /// The versions of the STOMP protocol the client supports.
    public static var acceptVersion: Self { "accept-version" }
    /// The name of a virtual host that the client wishes to connect to.
    public static var host: Self { "host" }
    /// The user identifier used to authenticate against a secured STOMP server.
    public static var login: Self { "login" }
    /// The password used to authenticate against a secured STOMP server.
    public static var passcode: Self { "passcode" }
    /// The Heart-beating settings.
    public static var heartBeat: Self { "heart-beat" }

    /// The version of the STOMP protocol the session will be using.
    public static var version: Self { "version" }
    /// A session identifier that uniquely identifies the session.
    public static var session: Self { "session" }
    /// A field that contains information about the STOMP server.
    public static var server: Self { "server" }

    /// The destination to which the client wants to subscribe or the destination the message was sent to.
    public static var destination: Self { "destination" }
    /// The transaction identifier.
    public static var transaction: Self { "transaction" }

    /// The `id` header allows the client and server to relate subsequent `MESSAGE` or `UNSUBSCRIBE` frames to the original subscription.
    public static var id: Self { "id" }
    /// The valid values for the ack header are `auto`, `client`, or `client-individual`. If the header is not set, it defaults to `auto`.
    public static var ack: Self { "ack" }

    /// A unique identifier for that message.
    public static var messageID: Self { "message-id" }
    /// The identifier of the subscription that is receiving the message.
    public static var subscription: Self { "subscription" }

    /// A `RECEIPT` frame MUST include the header `receipt-id`, where the value is the value of the `receipt` header in the frame which this is a receipt for.
    public static var receiptID: Self { "receipt-id" }

    /// A short description of the error.
    public static var message: Self { "message" }

    /// STOMP brokers may support the `selector` header
    /// which allows you to specify an [SQL 92 selector](http://activemq.apache.org/selectors.html) on the message headers
    /// which acts as a filter for content based routing.
    public static var selector: Self { "selector" }
}

extension STOMPHeader.Name: ExpressibleByStringLiteral {
    /// Create a STOMP header name from a string literal.
    ///
    /// - Parameter value: The string literal value.
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
