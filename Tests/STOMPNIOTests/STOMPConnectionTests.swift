import Foundation
import Logging
import NIOCore
import STOMPNIO
import Testing

#if canImport(Network)
import NIOTransportServices
#endif

@Suite("STOMPConnection Tests")
struct STOMPConnectionTests {
    static let hostname = ProcessInfo.processInfo.environment["RABBITMQ_SERVER"] ?? "localhost"

    @Test("Pub/Sub", .serialized, arguments: STOMPAckMode.allCases)
    func pubSub(ackMode: STOMPAckMode) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await STOMPConnection.withConnection(
                    host: Self.hostname,
                    port: 61613,
                    logger: self.subscriberLogger
                ) { connection in
                    try await connection.subscribe(to: "/queue/a", ackMode: ackMode) { subscription in
                        for try await frame in subscription {
                            #expect(String(buffer: frame.body) == "Hello, STOMP over NIO!")
                            return
                        }
                    }
                }
            }

            group.addTask {
                try await STOMPConnection.withConnection(
                    host: Self.hostname,
                    port: 61613,
                    logger: self.publisherLogger
                ) { connection in
                    try await connection.send(ByteBuffer(string: "Hello, STOMP over NIO!"), to: "/queue/a")
                }
            }

            try await group.waitForAll()
        }
    }

    @Test("Connect with Wrong Host and Port")
    func wrongHostAndPort() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await STOMPConnection.withConnection(
                host: "invalid-host",
                port: 12345,
                logger: self.logger
            ) { _ in }
        }
    }

    @Test("Connect with Wrong Credentials")
    func wrongCredentials() async throws {
        await #expect(throws: STOMPClientError.errorFrame(message: "Bad CONNECT", body: "Access refused for user 'wrong-user'")) {
            _ = try await STOMPConnection.withConnection(
                host: Self.hostname,
                port: 61613,
                configuration: .init(
                    authentication: .init(login: "wrong-user", passcode: "wrong-pass")
                ),
                logger: self.logger
            ) { _ in }
        }
    }

    @Test("Send Frame")
    func sendFrame() async throws {
        try await STOMPConnection.withConnection(
            host: Self.hostname,
            port: 61613,
            logger: self.logger
        ) { connection in
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
                host: Self.hostname,
                port: 61613,
                configuration: .init(connectTimeout: .milliseconds(1)),
                logger: self.logger
            ) { _ in }
        }
    }

    @Test("RECEIPT Timeout")
    func receiptTimeout() async throws {
        try await STOMPConnection.withConnection(
            host: Self.hostname,
            port: 61613,
            configuration: .init(receiptTimeout: .nanoseconds(1)),
            logger: self.logger
        ) { connection in
            let frame = STOMPFrame(
                command: .send,
                headers: [
                    STOMPHeader(name: "destination", value: "/queue/test"),
                    STOMPHeader(name: "content-type", value: "text/plain"),
                    STOMPHeader(name: "receipt", value: "sendFrame"),
                ],
                body: ByteBuffer(string: "Test Message")
            )

            await #expect(throws: STOMPClientError.timeout) {
                _ = try await connection.send(frame: frame)
            }
        }
    }

    @Test("Graceful Shutdown")
    func gracefulShutdown() async throws {
        try await STOMPConnection.withConnection(
            host: Self.hostname,
            port: 61613,
            logger: self.logger
        ) { connection in
            try await connection.triggerGracefulShutdown()
        }
    }

    @Test("Send after Graceful Shutdown")
    func sendAfterGracefulShutdown() async throws {
        try await STOMPConnection.withConnection(
            host: Self.hostname,
            port: 61613,
            logger: self.logger
        ) { connection in
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
            host: Self.hostname,
            port: 61613,
            eventLoop: NIOTSEventLoopGroup.singleton.any(),
            logger: self.logger
        ) { connection in
            let frame = STOMPFrame(
                command: .send,
                headers: [
                    STOMPHeader(name: "destination", value: "/queue/test"),
                    STOMPHeader(name: "content-type", value: "text/plain"),
                    STOMPHeader(name: "receipt", value: "nioTransportServicesConnection"),
                ],
                body: ByteBuffer(string: "Test Message")
            )
            let receiptFrame = try await connection.send(frame: frame)
            #expect(receiptFrame != nil)
            #expect(receiptFrame?.command == .receipt)
        }
    }
    #endif

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
