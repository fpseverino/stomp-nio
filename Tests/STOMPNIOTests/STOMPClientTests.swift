import Configuration
import Logging
import NIOCore
import NIOFoundationCompat
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

@Suite("STOMPClient Tests", .defaultLogger(logLevel: .trace))
struct STOMPClientTests {
    static let hostname = ProcessInfo.processInfo.environment["RABBITMQ_SERVER"] ?? "localhost"

    @Test("Pub/Sub", arguments: STOMPSubscription.AckMode.allCases, [STOMPClientConfiguration.WebSocket(), nil])
    func pubSub(ackMode: STOMPSubscription.AckMode, webSocket: STOMPClientConfiguration.WebSocket?) async throws {
        let client = STOMPClient(
            .hostname(Self.hostname, port: webSocket == nil ? 61613 : 15674),
            configuration: .init(webSocket: webSocket)
        )
        async let _ = client.run()

        try await withThrowingTaskGroup { group in
            group.addTask {
                try await client.subscribe(
                    to: "/queue/stomp-client-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")",
                    ackMode: ackMode
                ) { subscription in
                    for try await frame in subscription {
                        #expect(String(buffer: frame.body) == "Hello, STOMPClient!")
                        return
                    }
                }
            }

            group.addTask {
                try await client.send("Hello, STOMPClient!", to: "/queue/stomp-client-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")")
            }

            try await group.waitForAll()
        }
    }

    @Test(
        "Publish Large Payload",
        arguments: STOMPSubscription.AckMode.allCases, [STOMPClientConfiguration.WebSocket(maxFrameSize: 70000), nil]
    )
    func publishLargePayload(ackMode: STOMPSubscription.AckMode, webSocket: STOMPClientConfiguration.WebSocket?) async throws {
        let payloadData = Data(count: 65537)
        let payload = ByteBufferAllocator().buffer(data: payloadData)

        let client = STOMPClient(
            .hostname(Self.hostname, port: webSocket == nil ? 61613 : 15674),
            configuration: .init(webSocket: webSocket)
        )
        async let _ = client.run()

        try await withThrowingTaskGroup { group in
            group.addTask {
                try await client.subscribe(
                    to: "/queue/client-large-payload-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")",
                    ackMode: ackMode
                ) { subscription in
                    for try await frame in subscription {
                        var buffer = frame.body
                        let data = buffer.readData(length: buffer.readableBytes)
                        #expect(data == payloadData)
                        return
                    }
                }
            }

            group.addTask {
                try await client.send(
                    payload,
                    to: "/queue/client-large-payload-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")",
                    contentType: "application/octet-stream"
                )
            }

            try await group.waitForAll()
        }
    }

    #if os(macOS)
    @Test("Connect with Raw IP Address")
    func rawIPConnect() async throws {
        let client = STOMPClient(.hostname("127.0.0.1"))
        async let _ = client.run()

        try await client.send("Test", to: "/queue/client-raw-ip-address")
    }
    #endif

    @Test("Send Frame")
    func sendFrame() async throws {
        let client = STOMPClient(.hostname(Self.hostname))
        async let _ = client.run()

        let frame = STOMPFrame(
            command: .send,
            headers: [
                .destination: "/queue/send-frame",
                .contentType: "text/plain",
                .receipt: "sendFrame",
            ],
            body: ByteBuffer(string: "Test Message")
        )

        let receiptFrame = try await client.send(frame: frame)
        #expect(receiptFrame != nil)
        #expect(receiptFrame?.command == .receipt)
    }

    @Test("RECEIPT Timeout")
    func receiptTimeout() async throws {
        let client = STOMPClient(
            .hostname(Self.hostname),
            configuration: .init(receiptTimeout: .nanoseconds(1))
        )
        async let _ = client.run()

        await #expect(throws: STOMPClientError.timeout) {
            try await client.send("Test", to: "/queue/client-receipt-timeout")
        }
    }

    @Test("Connection Graceful Shutdown")
    func connectionGracefulShutdown() async throws {
        let client = STOMPClient(.hostname(Self.hostname))
        async let _ = client.run()

        try await client.withConnection { connection in
            try await connection.triggerGracefulShutdown()
            await #expect(throws: STOMPClientError.connectionClosed) {
                try await connection.send("Test", to: "/queue/client-graceful-shutdown")
            }
        }

        await #expect(throws: Never.self) {
            try await client.send("Test", to: "/queue/client-graceful-shutdown")
        }
    }

    #if canImport(Network)
    @Test("Connect with NIOTransportServices")
    func nioTransportServices() async throws {
        let client = STOMPClient(
            .hostname(Self.hostname),
            eventLoopGroup: NIOTSEventLoopGroup.singleton.any()
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
                        "stomp.login": "guest",
                        "stomp.passcode": "guest",
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
                configuration: .init(config: config.scoped(to: "stomp"))
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
                        "stomp.login": "guest",
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
                configuration: .init(config: config.scoped(to: "stomp"))
            )
            async let _ = client.run()

            try await client.send("Test", to: "/queue/client-config-reader")
        }
    }

    @Test("Shutdown")
    func shutdown() async throws {
        let client = STOMPClient(.hostname(Self.hostname))
        try await withThrowingTaskGroup { group in
            group.addTask {
                await client.run()
            }
            group.addTask {
                try await client.send("Test", to: "/queue/client-shutdown")
            }
            try await group.next()
            group.cancelAll()
        }
        await #expect(throws: STOMPClientError.clientIsShutDown) {
            try await client.send("Test", to: "/queue/client-shutdown")
        }
    }
}
