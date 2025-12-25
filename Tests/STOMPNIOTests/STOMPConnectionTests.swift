import Configuration
import Foundation
import Logging
import NIOCore
import NIOEmbedded
import NIOFoundationCompat
import STOMPNIO
import Testing

#if canImport(Network)
import NIOTransportServices
#endif

@Suite("STOMPConnection Tests", .serialized)
struct STOMPConnectionTests {
    static let hostname = ProcessInfo.processInfo.environment["RABBITMQ_SERVER"] ?? "localhost"

    @Test("Pub/Sub", arguments: STOMPAckMode.allCases)
    func pubSub(ackMode: STOMPAckMode) async throws {
        try await withThrowingTaskGroup { group in
            group.addTask {
                try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.subscriberLogger) { connection in
                    try await connection.subscribe(to: "/queue/a", ackMode: ackMode) { subscription in
                        for try await frame in subscription {
                            #expect(String(buffer: frame.body) == "Hello, STOMP over NIO!")
                            return
                        }
                    }
                }
            }

            group.addTask {
                try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.publisherLogger) { connection in
                    try await connection.send(ByteBuffer(string: "Hello, STOMP over NIO!"), to: "/queue/a")
                }
            }

            try await group.waitForAll()
        }
    }

    @Test("Publish Large Payload", arguments: STOMPAckMode.allCases)
    func publishLargePayload(ackMode: STOMPAckMode) async throws {
        let payloadSize = 65537
        let payloadData = Data(count: payloadSize)
        let payload = ByteBufferAllocator().buffer(data: payloadData)

        try await withThrowingTaskGroup { group in
            group.addTask {
                try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.subscriberLogger) { connection in
                    try await connection.subscribe(to: "/queue/a", ackMode: ackMode) { subscription in
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
                try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.publisherLogger) { connection in
                    try await connection.send(payload, to: "/queue/a")
                }
            }

            try await group.waitForAll()
        }
    }

    #if os(macOS)
    @Test("Connect with Raw IP Address")
    func rawIPConnect() async throws {
        try await STOMPConnection.withConnection(address: .hostname("127.0.0.1"), logger: self.logger) { connection in
            try await connection.send(ByteBuffer(string: "Test"), to: "/queue/test")
        }
    }
    #endif

    @Test("Connect with Wrong Host and Port")
    func wrongHostAndPort() async throws {
        await #expect(throws: (any Error).self) {
            try await STOMPConnection.withConnection(address: .hostname("invalid-host", port: 12345), logger: self.logger) { _ in }
        }
    }

    @Test("Connect with Wrong Credentials")
    func wrongCredentials() async throws {
        await #expect(throws: STOMPClientError.errorFrame(message: "Bad CONNECT", body: "Access refused for user 'wrong-user'")) {
            try await STOMPConnection.withConnection(
                address: .hostname(Self.hostname),
                configuration: .init(
                    authentication: .init(login: "wrong-user", passcode: "wrong-pass")
                ),
                logger: self.logger
            ) { _ in }
        }
    }

    @Test("Send Frame")
    func sendFrame() async throws {
        try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.logger) { connection in
            let frame = STOMPFrame(
                command: .send,
                headers: [
                    STOMPHeader(name: "destination", value: "/queue/test"),
                    STOMPHeader(name: "content-type", value: "text/plain"),
                    STOMPHeader(name: "receipt", value: "sendFrame"),
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
                configuration: .init(connectTimeout: .nanoseconds(1)),
                logger: self.logger
            ) { _ in }
        }
    }

    @Test("RECEIPT Timeout")
    func receiptTimeout() async throws {
        try await STOMPConnection.withConnection(
            address: .hostname(Self.hostname),
            configuration: .init(receiptTimeout: .nanoseconds(1)),
            logger: self.logger
        ) { connection in
            _ = await #expect(throws: STOMPClientError.timeout) {
                try await connection.send(ByteBuffer(string: "Test"), to: "/queue/test")
            }
        }
    }

    @Test("Graceful Shutdown")
    func gracefulShutdown() async throws {
        try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.logger) { connection in
            try await connection.triggerGracefulShutdown()
        }
    }

    @Test("Send after Graceful Shutdown")
    func sendAfterGracefulShutdown() async throws {
        try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.logger) { connection in
            try await connection.triggerGracefulShutdown()
            await #expect(throws: STOMPClientError.connectionClosed) {
                try await connection.send(ByteBuffer(string: "Test"), to: "/queue/test")
            }
        }
    }

    #if canImport(Network)
    @Test("Connect with NIOTransportServices")
    func nioTransportServices() async throws {
        try await STOMPConnection.withConnection(
            address: .hostname(Self.hostname),
            eventLoop: NIOTSEventLoopGroup.singleton.any(),
            logger: self.logger
        ) { connection in
            try await connection.send(ByteBuffer(string: "Test"), to: "/queue/test")
        }
    }
    #endif

    @Test("Configuration from ConfigReader")
    func configReader() async throws {
        let config = ConfigReader(
            provider: InMemoryProvider(
                values: [
                    "stomp.auth.login": "guest",
                    "stomp.auth.passcode": "guest",
                    "stomp.virtualHost": "/",
                    "stomp.connectTimeout": 15,
                    "stomp.receiptTimeout": 45,
                ]
            )
        )

        try await STOMPConnection.withConnection(
            address: .hostname(Self.hostname),
            configuration: .init(config: config),
            logger: self.logger
        ) { connection in
            try await connection.send(ByteBuffer(string: "Test"), to: "/queue/test")
        }
    }

    @Test("Cancellation")
    func cancellation() async throws {
        try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.logger) { connection in
            await withThrowingTaskGroup { group in
                group.addTask {
                    await #expect(throws: STOMPClientError.cancelledTask) {
                        try await connection.subscribe(to: "/queue/test") { subscription in
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

    @Test("Already Cancelled")
    func alreadyCancelled() async throws {
        try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.logger) { connection in
            await withThrowingTaskGroup(of: Void.self) { group in
                group.cancelAll()
                group.addTask {
                    await #expect(throws: STOMPClientError.cancelledTask) {
                        try await connection.subscribe(to: "/queue/test") { subscription in
                            for try await _ in subscription {
                                Issue.record("Should not receive messages")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Connection Close due to Cancellation")
    func connectionCloseDueToCancellation() async throws {
        let channel = NIOAsyncTestingChannel()
        let connection = try await STOMPConnection.setupChannelAndConnect(channel, logger: self.logger)
        try await channel.processConnect()

        try await withThrowingTaskGroup { group in
            group.addTask {
                await #expect(throws: STOMPClientError.connectionClosedDueToCancellation) {
                    try await connection.send(ByteBuffer(), to: "foo")
                }
            }
            try await withThrowingTaskGroup { group in
                group.addTask {
                    await #expect(throws: STOMPClientError.cancelledTask) {
                        try await connection.send(ByteBuffer(), to: "foo")
                    }
                }
                // wait for outbound write from both tasks
                _ = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
                _ = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
                group.cancelAll()
            }
        }
    }

    @Test("Transactions", arguments: STOMPAckMode.allCases)
    func transactions(ackMode: STOMPAckMode) async throws {
        try await STOMPConnection.withConnection(address: .hostname(Self.hostname), logger: self.logger) { connection in
            try await connection.withTransaction { transaction in
                try await withThrowingTaskGroup { group in
                    group.addTask {
                        try await transaction.subscribe(to: "/queue/transaction", ackMode: ackMode) { subscription in
                            for try await frame in subscription {
                                #expect(String(buffer: frame.body) == "Message in Transaction")
                                return
                            }
                        }
                    }

                    group.addTask {
                        try await transaction.send(ByteBuffer(string: "Message in Transaction"), to: "/queue/transaction")
                    }

                    try await group.waitForAll()
                }
            }
        }
    }

    let logger: Logger = {
        var logger = Logger(label: "STOMPConnectionTests")
        logger.logLevel = .trace
        return logger
    }()

    let subscriberLogger: Logger = {
        var logger = Logger(label: "Subscriber")
        logger.logLevel = .trace
        return logger
    }()

    let publisherLogger: Logger = {
        var logger = Logger(label: "Publisher")
        logger.logLevel = .trace
        return logger
    }()
}
