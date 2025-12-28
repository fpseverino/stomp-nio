import NIOCore
import NIOEmbedded
import STOMPNIO
import Testing

extension NIOAsyncTestingChannel {
    func processConnect(configuration: STOMPConnectionConfiguration = .init()) async throws {
        let connected = try await self.waitForOutboundWrite(as: ByteBuffer.self)
        var expectedBuffer = ByteBuffer()
        let heartBeatOutgoing = Int(configuration.heartBeat.outgoing.attoseconds / 1_000_000_000_000_000)
        let heartBeatIncoming = Int(configuration.heartBeat.incoming.attoseconds / 1_000_000_000_000_000)
        expectedBuffer.writeString(
            """
            CONNECT
            accept-version:1.0,1.1,1.2
            heart-beat:\(heartBeatOutgoing),\(heartBeatIncoming)

            \u{0}
            """
        )
        #expect(connected == expectedBuffer)
        try await self.writeInbound(
            ByteBuffer(
                string:
                    """
                    CONNECTED
                    heart-beat:\(heartBeatOutgoing),\(heartBeatIncoming)

                    \u{0}
                    """
            )
        )
    }
}
