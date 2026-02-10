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
