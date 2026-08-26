import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import STOMPNIO

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("STOMPConnection Tests", .defaultLogger(logLevel: .trace))
struct STOMPConnectionTests {
    @Test("Timed-out Task is removed before closing Connection")
    func timeoutClosingConnection() async throws {
        let channel = NIOAsyncTestingChannel()
        let connection = try await STOMPConnection.setupChannelAndConnect(
            channel,
            configuration: .init(receiptTimeout: .milliseconds(10))
        )
        try await channel.processConnect()

        try await withThrowingTaskGroup { group in
            group.addTask {
                _ = await #expect(throws: STOMPClientError.timeout) {
                    try await connection.send("Test", to: "/queue/timeout-closing-connection")
                }
            }

            _ = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
            await channel.testingEventLoop.advanceTime(to: .now())
            await channel.testingEventLoop.advanceTime(by: .milliseconds(20))
        }
    }

    @Test("Graceful Shutdown")
    func gracefulShutdown() async throws {
        let channel = NIOAsyncTestingChannel()
        let connection = try await STOMPConnection.setupChannelAndConnect(channel)
        try await channel.processConnect()

        let sendReceiptID = UUID().uuidString
        let sendFrame = STOMPFrame(command: .send, headers: [.receipt: sendReceiptID], body: .init(string: "Hi, mom!"))
        async let receipt = connection.send(frame: sendFrame)
        let send = try await channel.waitForOutboundWriteFrame()
        #expect(send == sendFrame)

        async let gracefulShutdown = connection.triggerGracefulShutdown()
        let disconnect = try await channel.waitForOutboundWriteFrame()
        #expect(disconnect.command == .disconnect)
        let disconnectReceiptID = try #require(disconnect.headers[.receipt])
        try await channel.writeInboundFrame(STOMPFrame(command: .receipt, headers: [.receiptID: disconnectReceiptID]))
        try await gracefulShutdown
        #expect(channel.isActive)

        let receiptFrame = STOMPFrame(command: .receipt, headers: [.receiptID: sendReceiptID])
        try await channel.writeInboundFrame(receiptFrame)

        #expect(!channel.isActive)

        try await #expect(receipt == receiptFrame)
    }

    @Test("Heart-beating with NIOAsyncTestingChannel")
    func heartBeatingTestingChannel() async throws {
        let channel = NIOAsyncTestingChannel()
        let configuration = STOMPConnectionConfiguration(heartBeat: (outgoing: .seconds(1), incoming: .seconds(1)))
        let _ = try await STOMPConnection.setupChannelAndConnect(channel, configuration: configuration)
        try await channel.processConnect(configuration: configuration)

        await channel.testingEventLoop.advanceTime(to: .now())
        for _ in 1...5 {
            await channel.testingEventLoop.advanceTime(by: .milliseconds(1100))

            let outbound = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
            #expect(outbound == ByteBuffer(string: "\n"))
        }
    }

    @Test("Cancellation does not Close Connection")
    func cancellationDoesNotCloseConnection() async throws {
        let channel = NIOAsyncTestingChannel()
        let connection = try await STOMPConnection.setupChannelAndConnect(channel)
        try await channel.processConnect()

        try await withThrowingTaskGroup { group in
            group.addTask {
                await #expect(throws: Never.self) {
                    try await connection.send(frame: STOMPFrame(command: .send, headers: [.receipt: "bar"]))
                }
            }
            try await withThrowingTaskGroup { group in
                group.addTask {
                    await #expect(throws: STOMPClientError.cancelled) {
                        try await connection.send(ByteBuffer(), to: "foo", contentType: "application/octet-stream")
                    }
                }
                // Wait for outbound write from both tasks
                _ = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
                _ = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
                group.cancelAll()
                // Send RECEIPT frame to unblock the first task
                let receiptFrame = ByteBuffer(string: "RECEIPT\nreceipt-id:bar\n\n\u{0}")
                try await channel.writeInbound(receiptFrame)
            }
        }
    }
}
