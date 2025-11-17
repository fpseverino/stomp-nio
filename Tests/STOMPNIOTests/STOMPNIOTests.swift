import Logging
import NIOCore
import Testing

@testable import STOMPNIO

@Suite("STOMP NIO Tests")
struct STOMPNIOTests {
    @Test("Pub/Sub", .serialized, arguments: STOMPAckMode.allCases)
    func pubSub(ackMode: STOMPAckMode) async throws {
        try await withThrowingTaskGroup { group in
            group.addTask {
                try await STOMPConnection.withConnection(
                    host: "localhost",
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
                    host: "localhost",
                    port: 61613,
                    logger: self.publisherLogger
                ) { connection in
                    try await connection.send(ByteBuffer(string: "Hello, STOMP over NIO!"), to: "/queue/a")
                }
            }

            try await group.waitForAll()
        }
    }

    @Test("Wrong Host and Port")
    func wrongHostAndPort() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await STOMPConnection.withConnection(
                host: "invalid-host",
                port: 12345,
                logger: self.publisherLogger
            ) { _ in }
        }
    }

    @Test("Wrong Credentials")
    func wrongCredentials() async throws {
        await #expect(throws: STOMPClientError.errorFrame(message: "Bad CONNECT", body: "Access refused for user 'wrong-user'")) {
            _ = try await STOMPConnection.withConnection(
                host: "localhost",
                port: 61613,
                configuration: .init(
                    authentication: .init(login: "wrong-user", passcode: "wrong-pass")
                ),
                logger: self.publisherLogger
            ) { _ in }
        }
    }

    @Test
    func execute() async throws {
        try await STOMPConnection.withConnection(
            host: "localhost",
            port: 61613,
            logger: self.subscriberLogger
        ) { connection in
            let subscribeFrame = STOMPFrame(
                command: .subscribe,
                headers: [
                    STOMPHeader(name: "destination", value: "destination"),
                    STOMPHeader(name: "id", value: "id"),
                    STOMPHeader(name: "ack", value: STOMPAckMode.auto.rawValue),
                    STOMPHeader(name: "receipt", value: "77"),
                ]
            )

            let receiptFrame = try await connection.execute(frame: subscribeFrame)
            #expect(receiptFrame != nil)
            #expect(receiptFrame?.command == .receipt)
        }
    }

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
