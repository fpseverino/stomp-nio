import Configuration
import Logging
import NIOCore
import NIOPosix
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

@Suite("TLS Tests", .serialized, .defaultLogger(logLevel: .trace))
struct TLSTests {
    static let hostname = ProcessInfo.processInfo.environment["RABBITMQ_SERVER"] ?? "localhost"

    @Suite("STOMPConnection Tests")
    struct STOMPConnectionTests {
        @Test("Connect with TLS", arguments: [STOMPConnectionConfiguration.WebSocket(), nil])
        func tlsConnect(webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
            try await STOMPConnection.withConnection(
                address: .hostname(TLSTests.hostname, port: webSocket == nil ? 61614 : 15673),
                configuration: .init(
                    tls: .enable(Self.getTLSConfiguration(), tlsServerName: "fpseverino.com"),
                    webSocket: webSocket
                ),
                eventLoop: TLSTests.eventLoopGroupSingleton.any()
            ) { connection in
                try await connection.send(
                    "Hello, STOMP over TLS\(webSocket == nil ? "" : " and WebSockets")!",
                    to: "/queue/tls-\(webSocket == nil ? "tcp" : "websocket")"
                )
            }

            // Try consuming the message with a standard unencrypted TCP connection
            try await STOMPConnection.withConnection(address: .hostname(TLSTests.hostname)) { connection in
                try await connection.subscribe(to: "/queue/tls-\(webSocket == nil ? "tcp" : "websocket")") { subscription in
                    for try await frame in subscription {
                        #expect(String(buffer: frame.body) == "Hello, STOMP over TLS\(webSocket == nil ? "" : " and WebSockets")!")
                        return
                    }
                }
            }
        }

        #if canImport(Network)
        @Test("Connect with TLS from P12")
        func tlsConnectFromP12() async throws {
            try await STOMPConnection.withConnection(
                address: .hostname(TLSTests.hostname, port: 61614),
                configuration: .init(
                    tls: .enable(
                        .ts(
                            .init(
                                trustRoots: .der(TLSTests.rootPath + "/Certs/ca.der"),
                                clientIdentity: .p12(
                                    filename: TLSTests.rootPath + "/Certs/client.p12",
                                    password: "STOMPNIOClientCertPassword"
                                )
                            )
                        ),
                        tlsServerName: "fpseverino.com"
                    )
                ),
                eventLoop: TLSTests.eventLoopGroupSingleton.any()
            ) { connection in
                try await connection.send("Test", to: "/queue/tls-p12")
            }
        }

        @Test("Connect with NIOTransportServices from ConfigReader")
        func tlsConnectWithConfigReader() async throws {
            let configReader = ConfigReader(
                provider: InMemoryProvider(
                    values: [
                        "tls.niots.trustRoots": .init(stringLiteral: TLSTests.rootPath + "/Certs/ca.der"),
                        "tls.niots.privateKey": .init(stringLiteral: TLSTests.rootPath + "/Certs/client.p12"),
                        "tls.niots.privateKeyPassword": "STOMPNIOClientCertPassword",
                        "tls.niots.serverName": "fpseverino.com",
                    ]
                )
            )
            try await STOMPConnection.withConnection(
                address: .hostname(TLSTests.hostname, port: 61614),
                configuration: .init(config: configReader),
                eventLoop: TLSTests.eventLoopGroupSingleton.any()
            ) { connection in
                try await connection.send("Test", to: "/queue/tls-config")
            }
        }
        #endif

        static func getTLSConfiguration(
            withTrustRoots: Bool = true,
            withClientKey: Bool = true
        ) throws -> STOMPConnectionConfiguration.TLS.Configuration {
            #if os(Linux) || os(Android)
            let rootCertificate = try NIOSSLCertificate.fromPEMFile(TLSTests.rootPath + "/Certs/ca.pem")
            let certificate = try NIOSSLCertificate.fromPEMFile(TLSTests.rootPath + "/Certs/client.pem")
            let privateKey = try NIOSSLPrivateKey(file: TLSTests.rootPath + "/Certs/client.key", format: .pem)
            var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
            tlsConfiguration.trustRoots = withTrustRoots ? .certificates(rootCertificate) : .default
            tlsConfiguration.certificateChain = withClientKey ? certificate.map { .certificate($0) } : []
            tlsConfiguration.privateKey = withClientKey ? .privateKey(privateKey) : nil
            return .niossl(tlsConfiguration)
            #else
            let caData = try Data(contentsOf: URL(fileURLWithPath: TLSTests.rootPath + "/Certs/ca.der"))
            let trustRootCertificates = SecCertificateCreateWithData(nil, caData as CFData).map { [$0] }
            let p12Data = try Data(contentsOf: URL(fileURLWithPath: TLSTests.rootPath + "/Certs/client.p12"))
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

    @Suite("STOMPClient Tests")
    struct STOMPClientTests {
        @Test("Connect with TLS", arguments: [STOMPClientConfiguration.WebSocket(), nil])
        func tlsConnect(webSocket: STOMPClientConfiguration.WebSocket?) async throws {
            let client = STOMPClient(
                .hostname(TLSTests.hostname, port: webSocket == nil ? 61614 : 15673),
                configuration: .init(
                    tls: .enable(try Self.getTLSConfiguration(), tlsServerName: "fpseverino.com"),
                    webSocket: webSocket
                ),
                eventLoopGroup: TLSTests.eventLoopGroupSingleton.any()
            )
            async let _ = client.run()
            try await client.send(
                "Hello, STOMPClient over TLS\(webSocket == nil ? "" : " and WebSockets")!",
                to: "/queue/client-tls-\(webSocket == nil ? "tcp" : "websocket")"
            )

            // Try consuming the message with a standard unencrypted TCP connection
            try await STOMPConnection.withConnection(address: .hostname(TLSTests.hostname)) { connection in
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
                .hostname(TLSTests.hostname, port: 61614),
                configuration: .init(
                    tls: .enable(
                        try .ts(
                            .init(
                                trustRoots: .der(TLSTests.rootPath + "/Certs/ca.der"),
                                clientIdentity: .p12(
                                    filename: TLSTests.rootPath + "/Certs/client.p12",
                                    password: "STOMPNIOClientCertPassword"
                                )
                            )
                        ),
                        tlsServerName: "fpseverino.com"
                    )
                ),
                eventLoopGroup: TLSTests.eventLoopGroupSingleton.any()
            )
            async let _ = client.run()
            try await client.send("Test", to: "/queue/client-tls-p12")
        }

        @Test("Connect with NIOTransportServices from ConfigReader")
        func tlsConnectWithConfigReader() async throws {
            let configReader = ConfigReader(
                provider: InMemoryProvider(
                    values: [
                        "tls.niots.trustRoots": .init(stringLiteral: TLSTests.rootPath + "/Certs/ca.der"),
                        "tls.niots.privateKey": .init(stringLiteral: TLSTests.rootPath + "/Certs/client.p12"),
                        "tls.niots.privateKeyPassword": "STOMPNIOClientCertPassword",
                        "tls.niots.serverName": "fpseverino.com",
                    ]
                )
            )
            let client = STOMPClient(
                .hostname(TLSTests.hostname, port: 61614),
                configuration: .init(config: configReader),
                eventLoopGroup: TLSTests.eventLoopGroupSingleton.any()
            )
            async let _ = client.run()
            try await client.send("Test", to: "/queue/client-tls-config")
        }
        #endif

        static func getTLSConfiguration(
            withTrustRoots: Bool = true,
            withClientKey: Bool = true
        ) throws -> STOMPClientConfiguration.TLS.Configuration {
            #if os(Linux) || os(Android)
            let rootCertificate = try NIOSSLCertificate.fromPEMFile(TLSTests.rootPath + "/Certs/ca.pem")
            let certificate = try NIOSSLCertificate.fromPEMFile(TLSTests.rootPath + "/Certs/client.pem")
            let privateKey = try NIOSSLPrivateKey(file: TLSTests.rootPath + "/Certs/client.key", format: .pem)
            var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
            tlsConfiguration.trustRoots = withTrustRoots ? .certificates(rootCertificate) : .default
            tlsConfiguration.certificateChain = withClientKey ? certificate.map { .certificate($0) } : []
            tlsConfiguration.privateKey = withClientKey ? .privateKey(privateKey) : nil
            return .niossl(tlsConfiguration)
            #else
            let caData = try Data(contentsOf: URL(fileURLWithPath: TLSTests.rootPath + "/Certs/ca.der"))
            let trustRootCertificates = SecCertificateCreateWithData(nil, caData as CFData).map { [$0] }
            let p12Data = try Data(contentsOf: URL(fileURLWithPath: TLSTests.rootPath + "/Certs/client.p12"))
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
}
