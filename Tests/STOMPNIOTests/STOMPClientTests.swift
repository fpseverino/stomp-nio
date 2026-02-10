import Logging
import NIOCore
import STOMPNIO
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Network)
import NIOTransportServices
#endif

#if os(macOS) || os(Linux) || os(Android)
import NIOSSL
#endif

@Suite("STOMPClient Tests")
struct STOMPClientTests {
    static let hostname = ProcessInfo.processInfo.environment["RABBITMQ_SERVER"] ?? "localhost"

    @Test("Pub/Sub", arguments: STOMPSubscription.AckMode.allCases, [STOMPClientConfiguration.WebSocket(), nil])
    func pubSub(ackMode: STOMPSubscription.AckMode, webSocket: STOMPClientConfiguration.WebSocket?) async throws {
        let client = STOMPClient(
            .hostname(Self.hostname, port: webSocket == nil ? 61613 : 15674),
            configuration: .init(webSocket: webSocket),
            logger: self.logger
        )
        async let _ = client.run()

        try await withThrowingTaskGroup { group in
            group.addTask {
                try await client.withConnection { connection in
                    try await connection.subscribe(
                        to: "/queue/stomp-client-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")",
                        ackMode: ackMode
                    ) { subscription in
                        for try await frame in subscription {
                            #expect(String(buffer: frame.body) == "Hello, STOMPClient!")
                            return
                        }
                    }
                }
            }

            group.addTask {
                try await client.send("Hello, STOMPClient!", to: "/queue/stomp-client-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")")
            }

            try await group.waitForAll()
        }
    }

    @Suite("TLS Tests", .serialized)
    struct TLSTests {
        @Test("Connect with TLS", arguments: [STOMPClientConfiguration.WebSocket(), nil])
        func tlsConnect(webSocket: STOMPClientConfiguration.WebSocket?) async throws {
            let client = STOMPClient(
                .hostname(STOMPClientTests.hostname, port: webSocket == nil ? 61614 : 15673),
                configuration: .init(
                    tls: .enable(try Self.getTLSConfiguration(), tlsServerName: "fpseverino.com"),
                    webSocket: webSocket
                ),
                eventLoopGroup: Self.eventLoopGroupSingleton.any(),
                logger: self.logger
            )
            async let _ = client.run()
            try await client.send(
                "Hello, STOMPClient over TLS\(webSocket == nil ? "" : " and WebSockets")!",
                to: "/queue/client-tls-\(webSocket == nil ? "tcp" : "websocket")"
            )

            // Try consuming the message with a standard unencrypted TCP connection
            try await STOMPConnection.withConnection(address: .hostname(STOMPClientTests.hostname), logger: self.logger) { connection in
                try await connection.subscribe(to: "/queue/client-tls-\(webSocket == nil ? "tcp" : "websocket")") { subscription in
                    for try await frame in subscription {
                        #expect(String(buffer: frame.body) == "Hello, STOMPClient over TLS\(webSocket == nil ? "" : " and WebSockets")!")
                        return
                    }
                }
            }
        }

        #if canImport(Network)
        @Test("Connect with TLS from P12")
        func tlsConnectFromP12() async throws {
            let client = STOMPClient(
                .hostname(STOMPClientTests.hostname, port: 61614),
                configuration: .init(
                    tls: .enable(
                        try .ts(
                            .init(
                                trustRoots: .der(Self.rootPath + "/Certs/ca.der"),
                                clientIdentity: .p12(
                                    filename: Self.rootPath + "/Certs/client.p12",
                                    password: "STOMPNIOClientCertPassword"
                                )
                            )
                        ),
                        tlsServerName: "fpseverino.com"
                    )
                ),
                eventLoopGroup: Self.eventLoopGroupSingleton.any(),
                logger: self.logger
            )
            async let _ = client.run()
            try await client.send("Test", to: "/queue/client-tls-p12")
        }
        #endif

        let logger: Logger = {
            var logger = Logger(label: "TLSTests")
            logger.logLevel = .trace
            return logger
        }()

        static let rootPath = #filePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .dropLast(3)
            .joined(separator: "/")

        static var eventLoopGroupSingleton: any EventLoopGroup {
            #if canImport(Network)
            // Return TS Eventloop for non-Linux builds, as we use TS TLS
            NIOTSEventLoopGroup.singleton
            #else
            MultiThreadedEventLoopGroup.singleton
            #endif
        }

        static func getTLSConfiguration(
            withTrustRoots: Bool = true,
            withClientKey: Bool = true
        ) throws -> STOMPClientConfiguration.TLS.Configuration {
            #if os(Linux) || os(Android)
            let rootCertificate = try NIOSSLCertificate.fromPEMFile(Self.rootPath + "/Certs/ca.pem")
            let certificate = try NIOSSLCertificate.fromPEMFile(Self.rootPath + "/Certs/client.pem")
            let privateKey = try NIOSSLPrivateKey(file: Self.rootPath + "/Certs/client.key", format: .pem)
            var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
            tlsConfiguration.trustRoots = withTrustRoots ? .certificates(rootCertificate) : .default
            tlsConfiguration.certificateChain = withClientKey ? certificate.map { .certificate($0) } : []
            tlsConfiguration.privateKey = withClientKey ? .privateKey(privateKey) : nil
            return .niossl(tlsConfiguration)
            #else
            let caData = try Data(contentsOf: URL(fileURLWithPath: Self.rootPath + "/Certs/ca.der"))
            let trustRootCertificates = SecCertificateCreateWithData(nil, caData as CFData).map { [$0] }
            let p12Data = try Data(contentsOf: URL(fileURLWithPath: Self.rootPath + "/Certs/client.p12"))
            let options: [String: String] = [kSecImportExportPassphrase as String: "STOMPNIOClientCertPassword"]
            var rawItems: CFArray?
            guard SecPKCS12Import(p12Data as CFData, options as CFDictionary, &rawItems) == errSecSuccess else {
                throw STOMPClientError.wrongTLSConfig
            }
            guard
                let items = rawItems as? [[String: Any]],
                let firstItem = items.first
            else {
                throw STOMPClientError.wrongTLSConfig
            }
            let identity = firstItem[kSecImportItemIdentity as String] as! SecIdentity?
            let tlsConfiguration = TSTLSConfiguration(
                trustRoots: withTrustRoots ? trustRootCertificates : nil,
                clientIdentity: withClientKey ? identity : nil
            )
            return .ts(tlsConfiguration)
            #endif
        }
    }

    #if canImport(Network)
    @Test("Connect with NIOTransportServices")
    func nioTransportServices() async throws {
        let client = STOMPClient(
            .hostname(Self.hostname),
            eventLoopGroup: NIOTSEventLoopGroup.singleton.any(),
            logger: self.logger
        )
        async let _ = client.run()
        try await client.send("Test", to: "/queue/client-nio-transport-services")
    }
    #endif

    let logger: Logger = {
        var logger = Logger(label: "STOMPClientTests")
        logger.logLevel = .trace
        return logger
    }()
}
