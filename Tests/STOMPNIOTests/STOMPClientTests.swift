import Configuration
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

    #if os(macOS)
    @Test("Connect with Raw IP Address")
    func rawIPConnect() async throws {
        let client = STOMPClient(.hostname("127.0.0.1"), logger: self.logger)
        async let _ = client.run()

        try await client.send("Test", to: "/queue/client-raw-ip-address")
    }
    #endif

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

    @Suite("ConfigReader Tests")
    struct ConfigReaderTests {
        @Test("Configuration from ConfigReader")
        func configReader() async throws {
            let config = ConfigReader(
                provider: InMemoryProvider(
                    values: [
                        "stomp.auth.login": "guest",
                        "stomp.auth.passcode": "guest",
                        "stomp.virtualHost": "/",
                        "stomp.heartBeat.outgoing": 1000,
                        "stomp.heartBeat.incoming": 1000,
                        "stomp.connectTimeout": 15,
                        "stomp.receiptTimeout": 45,
                        "stomp.connectHeaders": ConfigValue(
                            .stringArray(["header1:value1", "header2: value2"]),
                            isSecret: false
                        ),
                        "stomp.webSocket.initialRequestHeaders": ConfigValue(
                            .stringArray(["X-Custom-Header: CustomValue", "X-Another-Header: AnotherValue"]),
                            isSecret: false
                        ),
                    ]
                )
            )

            let client = STOMPClient(
                .hostname(STOMPConnectionTests.hostname, port: 15674),
                configuration: .init(config: config),
                logger: self.logger
            )
            async let _ = client.run()

            try await Task.sleep(for: .seconds(5))
            try await client.send("Test", to: "/queue/client-config-reader")
        }

        @Test("Missing Configuration Values")
        func missingConfigValues() async throws {
            let config = ConfigReader(
                provider: InMemoryProvider(
                    values: [
                        "stomp.auth.login": "guest",
                        "stomp.virtualHost": "/",
                        "stomp.heartBeat.outgoing": 1000,
                        "stomp.connectTimeout": 15,
                        "stomp.receiptTimeout": 45,
                        "stomp.connectHeaders": ConfigValue(
                            .stringArray(["invalid-header", "header2: value2"]),
                            isSecret: false
                        ),
                    ]
                )
            )

            let client = STOMPClient(
                .hostname(STOMPConnectionTests.hostname),
                configuration: .init(config: config),
                logger: self.logger
            )
            async let _ = client.run()

            try await client.send("Test", to: "/queue/client-config-reader")
        }

        let logger: Logger = {
            var logger = Logger(label: "ConfigReaderTests")
            logger.logLevel = .trace
            return logger
        }()
    }

    let logger: Logger = {
        var logger = Logger(label: "STOMPClientTests")
        logger.logLevel = .trace
        return logger
    }()
}
