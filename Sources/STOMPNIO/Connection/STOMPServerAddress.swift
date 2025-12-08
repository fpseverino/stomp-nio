/// A STOMP broker address to connect to.
public struct STOMPServerAddress: Sendable, Equatable, Hashable {
    enum _Internal: Equatable, Hashable {
        case hostname(_ host: String, port: Int)
        case unixDomainSocket(path: String)
    }

    let value: _Internal
    init(_ value: _Internal) {
        self.value = value
    }

    // Address defined by host and port.
    public static func hostname(_ host: String, port: Int = 61613) -> Self { .init(.hostname(host, port: port)) }
    // Address defined by Unix domain socket.
    public static func unixDomainSocket(path: String) -> Self { .init(.unixDomainSocket(path: path)) }
}
