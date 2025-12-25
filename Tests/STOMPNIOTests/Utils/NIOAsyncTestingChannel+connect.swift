import NIOCore
import NIOEmbedded
import Testing

@testable import STOMPNIO

extension NIOAsyncTestingChannel {
    func processConnect() async throws {
        let connected = try await self.waitForOutboundWrite(as: ByteBuffer.self)
        var expectedBuffer = ByteBuffer()
        expectedBuffer.writeString("CONNECT\naccept-version:1.0,1.1,1.2\n\n\u{0}")
        #expect(connected == expectedBuffer)
        try await self.writeInbound(ByteBuffer(string: "CONNECTED\n\n\u{0}"))
    }
}
