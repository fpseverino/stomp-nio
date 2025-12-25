/// Errors returned by a STOMP client.
public struct STOMPClientError: Error, Sendable, Equatable {
    public struct ErrorType: Sendable, Hashable, CustomStringConvertible, Equatable {
        enum Base: String, Sendable, Equatable {
            case connectionClosing
            case connectionClosed
            /// An ERROR frame was received from the server
            case errorFrame
            /// A unexpected frame was received from the server
            case unsolicitedFrame
            /// The Task was cancelled
            case cancelledTask
            /// An expected header is missing from a frame
            case missingHeader
            /// Connection closed because it timed out while waiting for RECEIPT or CONNECTED frame
            case timeout
        }

        let base: Base

        private init(_ base: Base) {
            self.base = base
        }

        public static let connectionClosing = Self(.connectionClosing)
        public static let connectionClosed = Self(.connectionClosed)
        /// An ERROR frame was received from the server
        public static let errorFrame = Self(.errorFrame)
        /// A unexpected frame was received from the server
        public static let unsolicitedFrame = Self(.unsolicitedFrame)
        /// The Task was cancelled
        public static let cancelledTask = Self(.cancelledTask)
        /// An expected header is missing from a frame
        public static let missingHeader = Self(.missingHeader)
        /// Connection closed because it timed out while waiting for RECEIPT or CONNECTED frame
        public static let timeout = Self(.timeout)

        public var description: String {
            self.base.rawValue
        }
    }

    private struct Backing: Sendable, Equatable {
        fileprivate let errorType: ErrorType
        fileprivate let message: String?
        fileprivate let body: String?

        init(
            errorType: ErrorType,
            message: String? = nil,
            body: String? = nil
        ) {
            self.errorType = errorType
            self.message = message
            self.body = body
        }

        static func == (lhs: Backing, rhs: Backing) -> Bool {
            lhs.errorType == rhs.errorType
        }
    }

    private let backing: Backing

    public var errorType: ErrorType { backing.errorType }
    public var message: String? { backing.message }
    /// Body associated with the ERROR frame
    public var body: String? { backing.body }

    private init(backing: Backing) {
        self.backing = backing
    }

    private init(errorType: ErrorType) {
        self.backing = .init(errorType: errorType)
    }

    public static let connectionClosing = Self(errorType: .connectionClosing)

    public static let connectionClosed = Self(errorType: .connectionClosed)

    /// An ERROR frame was received from the server
    ///
    /// - Parameters:
    ///   - message: The message header from the ERROR frame
    ///   - body: The body of the ERROR frame
    public static func errorFrame(message: String?, body: String) -> Self {
        .init(backing: .init(errorType: .errorFrame, message: message, body: body))
    }

    /// A unexpected frame was received from the server
    ///
    /// - Parameter message: Description of the unexpected frame
    public static func unsolicitedFrame(message: String) -> Self {
        .init(backing: .init(errorType: .unsolicitedFrame, message: message))
    }

    /// The Task was cancelled
    public static let cancelledTask = Self(errorType: .cancelledTask)

    /// An expected header is missing from a frame
    ///
    /// - Parameter message: The missing header
    public static func missingHeader(message: String) -> Self {
        .init(backing: .init(errorType: .missingHeader, message: message))
    }

    /// Connection closed because it timed out while waiting for RECEIPT or CONNECTED frame
    public static let timeout = Self(errorType: .timeout)

    public static func == (lhs: STOMPClientError, rhs: STOMPClientError) -> Bool {
        lhs.backing == rhs.backing
    }
}

extension STOMPClientError: CustomStringConvertible {
    public var description: String {
        var result = "STOMPClientError(errorType: \(self.errorType)"
        if let message { result += ", message: \(message)" }
        if let body { result += ", body: \(body)" }
        result += ")"
        return result
    }
}
