import Configuration
import Foundation
import Logging
import NIOCore
import NIOFoundationCompat
import STOMPNIO
import Testing

#if canImport(Network)
import NIOTransportServices
#endif

@Suite("STOMPConnection Tests", .defaultLogger(logLevel: .trace))
struct STOMPConnectionTests {
    static let hostname = ProcessInfo.processInfo.environment["RABBITMQ_SERVER"] ?? "localhost"

    @Test("Pub/Sub", arguments: STOMPSubscription.AckMode.allCases, [STOMPConnectionConfiguration.WebSocket(), nil])
    func pubSub(ackMode: STOMPSubscription.AckMode, webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
        try await withThrowingTaskGroup { group in
            group.addTask {
                try await STOMPConnection.withConnection(
                    address: .hostname(Self.hostname, port: webSocket == nil ? 61613 : 15674),
                    configuration: .init(webSocket: webSocket)
                ) { connection in
                    try await connection.subscribe(
                        to: "/queue/stomp-nio-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")",
                        ackMode: ackMode
                    ) { subscription in
                        for try await frame in subscription {
                            #expect(String(buffer: frame.body) == "Hello, STOMP over NIO!")
                            return
                        }
                    }
                }
            }

            group.addTask {
                try await STOMPConnection.withConnection(
                    address: .hostname(Self.hostname, port: webSocket == nil ? 61613 : 15674),
                    configuration: .init(webSocket: webSocket)
                ) { connection in
                    try await connection.send(
                        "Hello, STOMP over NIO!",
                        to: "/queue/stomp-nio-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")"
                    )
                }
            }

            try await group.waitForAll()
        }
    }

    @Test(
        "Publish Large Payload",
        arguments: STOMPSubscription.AckMode.allCases, [STOMPConnectionConfiguration.WebSocket(maxFrameSize: 70000), nil]
    )
    func publishLargePayload(ackMode: STOMPSubscription.AckMode, webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
        let payloadData = Data(count: 65537)
        let payload = ByteBufferAllocator().buffer(data: payloadData)

        try await withThrowingTaskGroup { group in
            group.addTask {
                try await STOMPConnection.withConnection(
                    address: .hostname(Self.hostname, port: webSocket == nil ? 61613 : 15674),
                    configuration: .init(webSocket: webSocket)
                ) { connection in
                    try await connection.subscribe(
                        to: "/queue/large-payload-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")",
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
            }

            group.addTask {
                try await STOMPConnection.withConnection(
                    address: .hostname(Self.hostname, port: webSocket == nil ? 61613 : 15674),
                    configuration: .init(webSocket: webSocket)
                ) { connection in
                    try await connection.send(
                        payload,
                        to: "/queue/large-payload-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")",
                        contentType: "application/octet-stream"
                    )
                }
            }

            try await group.waitForAll()
        }
    }

    #if os(macOS)
    @Test("Connect with Raw IP Address")
    func rawIPConnect() async throws {
        try await STOMPConnection.withConnection(address: .hostname("127.0.0.1")) { connection in
            try await connection.send("Test", to: "/queue/raw-ip-address")
        }
    }
    #endif

    @Test("Connect with Wrong Host and Port")
    func wrongHostAndPort() async throws {
        await #expect(throws: (any Error).self) {
            try await STOMPConnection.withConnection(address: .hostname("invalid-host", port: 12345)) { _ in }
        }
    }

    @Test("Connect with Wrong Credentials")
    func wrongCredentials() async throws {
        await #expect(throws: STOMPClientError.errorFrame(message: "Bad CONNECT", body: "Access refused for user 'wrong-user'")) {
            try await STOMPConnection.withConnection(
                address: .hostname(Self.hostname),
                configuration: .init(login: "wrong-user", passcode: "wrong-pass")
            ) { _ in }
        }
    }

    @Test("Send Frame")
    func sendFrame() async throws {
        try await STOMPConnection.withConnection(address: .hostname(Self.hostname)) { connection in
            let frame = STOMPFrame(
                command: .send,
                headers: [
                    .destination: "/queue/send-frame",
                    .contentType: "text/plain",
                    .receipt: "sendFrame",
                ],
                body: ByteBuffer(string: "Test Message")
            )

            let receiptFrame = try await connection.send(frame: frame)
            #expect(receiptFrame != nil)
            #expect(receiptFrame?.command == .receipt)
        }
    }

    @Test("CONNECTED Timeout")
    func connectedTimeout() async throws {
        await #expect(throws: STOMPClientError.timeout) {
            try await STOMPConnection.withConnection(
                address: .hostname(Self.hostname),
                configuration: .init(connectTimeout: .nanoseconds(1))
            ) { _ in }
        }
    }

    @Test("RECEIPT Timeout")
    func receiptTimeout() async throws {
        try await STOMPConnection.withConnection(
            address: .hostname(Self.hostname),
            configuration: .init(receiptTimeout: .nanoseconds(1))
        ) { connection in
            _ = await #expect(throws: STOMPClientError.timeout) {
                try await connection.send("Test", to: "/queue/receipt-timeout")
            }
        }
    }

    @Test("Send after Graceful Shutdown")
    func sendAfterGracefulShutdown() async throws {
        try await STOMPConnection.withConnection(address: .hostname(Self.hostname)) { connection in
            try await connection.triggerGracefulShutdown()
            await #expect(throws: STOMPClientError.connectionClosed) {
                try await connection.send("Test", to: "/queue/graceful-shutdown")
            }
        }
    }

    #if canImport(Network)
    @Test("Connect with NIOTransportServices")
    func nioTransportServices() async throws {
        try await STOMPConnection.withConnection(
            address: .hostname(Self.hostname),
            eventLoop: NIOTSEventLoopGroup.singleton.any()
        ) { connection in
            try await connection.send("Test", to: "/queue/nio-transport-services")
        }
    }
    #endif

    @Suite("Heart-beating Tests")
    struct HeartBeatingTests {
        @Test("Heart-beating with Real Broker", arguments: [STOMPConnectionConfiguration.WebSocket(), nil])
        func heartBeatingBroker(webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname, port: webSocket == nil ? 61613 : 15674),
                configuration: .init(heartBeat: (outgoing: .seconds(1), incoming: .seconds(1)), webSocket: webSocket)
            ) { connection in
                try await Task.sleep(for: .seconds(5))
                try await connection.send(
                    "Test after heart-beating",
                    to: "/queue/heart-beating-broker-\(webSocket == nil ? "tcp" : "websocket")"
                )
            }
        }

        @Test("Send Heart-beat", arguments: [STOMPConnectionConfiguration.WebSocket(), nil])
        func sendHeartBeat(webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname, port: webSocket == nil ? 61613 : 15674),
                configuration: .init(webSocket: webSocket)
            ) { connection in
                try await connection.heartBeat()
                try await connection.triggerGracefulShutdown()
            }
        }
    }

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

            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname, port: 15674),
                configuration: .init(config: config.scoped(to: "stomp"))
            ) { connection in
                try await Task.sleep(for: .seconds(5))
                try await connection.send("Test", to: "/queue/config-reader")
            }
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

            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname),
                configuration: .init(config: config.scoped(to: "stomp"))
            ) { connection in
                try await connection.send("Test", to: "/queue/config-reader")
            }
        }
    }

    @Suite("Cancellation Tests")
    struct CancellationTests {
        @Test("Cancellation", arguments: [STOMPConnectionConfiguration.WebSocket(), nil])
        func cancellation(webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname, port: webSocket == nil ? 61613 : 15674),
                configuration: .init(webSocket: webSocket)
            ) { connection in
                await withThrowingTaskGroup { group in
                    group.addTask {
                        await #expect(throws: STOMPClientError.cancelled) {
                            try await connection.subscribe(to: "/queue/cancellation") { subscription in
                                for try await _ in subscription {
                                    Issue.record("Should not receive messages")
                                }
                            }
                        }
                    }
                    group.cancelAll()
                }
            }
        }

        @Test("Already Cancelled", arguments: [STOMPConnectionConfiguration.WebSocket(), nil])
        func alreadyCancelled(webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname, port: webSocket == nil ? 61613 : 15674),
                configuration: .init(webSocket: webSocket)
            ) { connection in
                await withThrowingTaskGroup(of: Void.self) { group in
                    group.cancelAll()
                    group.addTask {
                        await #expect(throws: STOMPClientError.cancelled) {
                            try await connection.subscribe(to: "/queue/already-cancelled") { subscription in
                                for try await _ in subscription {
                                    Issue.record("Should not receive messages")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Suite("Transactions Tests")
    struct TransactionsTests {
        @Test("Subscription Transaction", arguments: STOMPSubscription.AckMode.allCases, [STOMPConnectionConfiguration.WebSocket(), nil])
        func subscriptionTransaction(ackMode: STOMPSubscription.AckMode, webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname, port: webSocket == nil ? 61613 : 15674),
                configuration: .init(webSocket: webSocket)
            ) { connection in
                try await connection.withTransaction { transaction in
                    try await withThrowingTaskGroup { group in
                        group.addTask {
                            try await transaction.subscribe(
                                to: "/queue/sub-transaction-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")",
                                ackMode: ackMode
                            ) { subscription in
                                for try await frame in subscription {
                                    #expect(String(buffer: frame.body) == "Message in Transaction")
                                    return
                                }
                            }
                        }

                        group.addTask {
                            try await connection.send(
                                "Message in Transaction",
                                to: "/queue/sub-transaction-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")"
                            )
                        }

                        try await group.waitForAll()
                    }
                }
            }

            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname, port: webSocket == nil ? 61613 : 15674),
                configuration: .init(webSocket: webSocket)
            ) { connection in
                try await withThrowingTaskGroup { group in
                    group.addTask {
                        try await connection.subscribe(
                            to: "/queue/sub-transaction-\(ackMode)-\(webSocket == nil ? "tcp" : "websocket")",
                            ackMode: ackMode
                        ) { subscription in
                            for try await _ in subscription {
                                Issue.record("Should not receive the message, as the transaction has been aborted")
                            }
                        }
                    }

                    // Give some time for the message to be (not) delivered
                    try await Task.sleep(for: .seconds(1))
                    group.cancelAll()
                }
            }
        }

        @Test("Send Transaction", arguments: [STOMPConnectionConfiguration.WebSocket(), nil])
        func sendTransaction(webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname, port: webSocket == nil ? 61613 : 15674),
                configuration: .init(webSocket: webSocket)
            ) { connection in
                try await withThrowingTaskGroup { group in
                    group.addTask {
                        try await connection.withTransaction { transaction in
                            try await transaction.send(
                                "Message in Transaction",
                                to: "/queue/send-transaction-\(webSocket == nil ? "tcp" : "websocket")"
                            )
                        }
                    }

                    group.addTask {
                        try await connection.subscribe(
                            to: "/queue/send-transaction-\(webSocket == nil ? "tcp" : "websocket")"
                        ) { subscription in
                            for try await frame in subscription {
                                #expect(String(buffer: frame.body) == "Message in Transaction")
                                return
                            }
                        }
                    }

                    try await group.waitForAll()
                }
            }
        }

        @Test("Abort Subscription Transaction", arguments: [STOMPSubscription.AckMode.client, .clientIndividual])
        func abortSubscriptionTransaction(ackMode: STOMPSubscription.AckMode) async throws {
            try await STOMPConnection.withConnection(address: .hostname(STOMPConnectionTests.hostname)) { connection in
                try? await connection.withTransaction { transaction in
                    try await withThrowingTaskGroup { group in
                        group.addTask {
                            try await transaction.subscribe(
                                to: "/queue/abort-sub-transaction-\(ackMode)",
                                ackMode: ackMode
                            ) { subscription in
                                for try await frame in subscription {
                                    // The message is received and the ACK is sent, but as part of the transaction
                                    #expect(String(buffer: frame.body) == "Message in Transaction")
                                    return
                                }
                            }
                        }

                        group.addTask {
                            try await connection.send("Message in Transaction", to: "/queue/abort-sub-transaction-\(ackMode)")
                        }

                        try await group.waitForAll()
                    }

                    throw AbortTransaction()
                    // The automatic ACK, sent during the transaction, is rolled back
                }
            }

            try await STOMPConnection.withConnection(address: .hostname(STOMPConnectionTests.hostname)) { connection in
                try await connection.subscribe(to: "/queue/abort-sub-transaction-\(ackMode)", ackMode: .clientIndividual) { subscription in
                    for try await frame in subscription {
                        // The queue still has the message, since the ACK was rolled back
                        #expect(String(buffer: frame.body) == "Message in Transaction")
                        return
                    }
                }
            }
        }

        @Test("Abort Send Transaction", arguments: [STOMPConnectionConfiguration.WebSocket(), nil])
        func abortSendTransaction(webSocket: STOMPConnectionConfiguration.WebSocket?) async throws {
            try await STOMPConnection.withConnection(
                address: .hostname(STOMPConnectionTests.hostname, port: webSocket == nil ? 61613 : 15674),
                configuration: .init(webSocket: webSocket)
            ) { connection in
                try await withThrowingTaskGroup { group in
                    group.addTask {
                        try await connection.withTransaction { transaction in
                            try await transaction.send(
                                "Message in Transaction",
                                to: "/queue/abort-send-transaction-\(webSocket == nil ? "tcp" : "websocket")"
                            )
                            throw AbortTransaction()
                        }
                    }

                    group.addTask {
                        try await connection.subscribe(
                            to: "/queue/abort-send-transaction-\(webSocket == nil ? "tcp" : "websocket")"
                        ) { subscription in
                            for try await _ in subscription {
                                Issue.record("Should not receive the message, as it was sent in a transaction that was aborted")
                            }
                        }
                    }

                    // Give some time for the message to be (not) delivered
                    try await Task.sleep(for: .seconds(1))
                    group.cancelAll()
                }
            }
        }

        struct AbortTransaction: Error {}
    }
}
