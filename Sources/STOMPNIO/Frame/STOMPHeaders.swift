/// A collection of STOMP headers.
public struct STOMPHeaders: Sendable, Hashable {
    var headers: [STOMPHeader]

    /// Create an empty collection of STOMP headers.
    public init() {
        self.headers = []
    }

    /// Create a collection of STOMP headers.
    public init(headers: [STOMPHeader]) {
        self.headers = headers
    }

    /// Whether one or more header with this name exists in the headers.
    ///
    /// - Parameter name: The name of the header to check for.
    ///
    /// - Returns: `true` if one or more headers with the given name exist, otherwise `false`.
    public func contains(_ name: STOMPHeader.Name) -> Bool {
        self.headers.contains { $0.name == name }
    }

    /// Get the first value for the given header name.
    ///
    /// - Parameter name: The name of the header.
    ///
    /// - Returns: The value of the header, or `nil` if the header does not exist.
    public subscript(name: STOMPHeader.Name) -> String? {
        self.headers.first { $0.name == name }?.value
    }

    /// Get all values for the given header name as an array of strings.
    /// The order of headers is preserved.
    ///
    /// - Parameter name: The name of the header.
    ///
    /// - Returns: An array of values for the header. If the header does not exist, an empty array is returned.
    public subscript(values name: STOMPHeader.Name) -> [String] {
        self.headers.filter { $0.name == name }.map { $0.value }
    }

    /// Get all headers with the given name.
    /// The order of headers is preserved.
    ///
    /// - Parameter name: The name of the header.
    ///
    /// - Returns: An array of headers. If the header does not exist, an empty array is returned.
    public subscript(headers name: STOMPHeader.Name) -> [STOMPHeader] {
        self.headers.filter { $0.name == name }
    }
}

extension STOMPHeaders: ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    /// Create a collection of STOMP headers from an array literal of ``STOMPHeader``s.
    ///
    /// - Parameter elements: The ``STOMPHeader``s.
    public init(arrayLiteral elements: STOMPHeader...) {
        self.headers = elements
    }

    /// Create a collection of STOMP headers from a dictionary literal.
    ///
    /// - Parameter elements: The key-value pairs representing header names and values.
    public init(dictionaryLiteral elements: (STOMPHeader.Name, String)...) {
        self.headers = elements.map { STOMPHeader(name: $0.0, value: $0.1) }
    }
}

extension STOMPHeaders: RangeReplaceableCollection, RandomAccessCollection, MutableCollection {
    /// The position of the first STOMP header.
    public var startIndex: Int {
        self.headers.startIndex
    }

    /// The position after the last STOMP header.
    public var endIndex: Int {
        self.headers.endIndex
    }

    /// A Boolean value indicating whether the `STOMPHeaders` collection is empty.
    public var isEmpty: Bool {
        self.headers.isEmpty
    }

    /// Accesses the ``STOMPHeader`` at the specified position.
    ///
    /// - Parameter position: The position of the element to access.
    ///   `position` must be greater than or equal to ``STOMPHeaders/startIndex`` and less than ``STOMPHeaders/endIndex``.
    public subscript(position: Int) -> STOMPHeader {
        get { self.headers[position] }
        set { self.headers[position] = newValue }
    }

    /// Replace the specified subrange of headers with the given new elements.
    ///
    /// - Parameters:
    ///   - subrange: The range of headers to replace.
    ///   - newElements: The new headers to insert into the specified range.
    public mutating func replaceSubrange<C>(_ subrange: Range<Index>, with newElements: C)
    where C: Collection, Element == C.Element {
        self.headers.replaceSubrange(subrange, with: newElements)
    }
}
