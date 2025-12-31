import NIOCore
import Testing

@testable import STOMPNIO

@Suite("STOMPFrameDecoder Tests")
struct STOMPFrameDecoderTests {
    @Test("Decode simple CONNECT Frame")
    func decodeSimpleConnectFrame() throws {
        let decoder = STOMPFrameDecoder()

        var buffer = ByteBufferAllocator().buffer(capacity: 64)
        buffer.writeString("CONNECT\n")
        buffer.writeString("accept-version:1.2\n")
        buffer.writeString("host:stomp.github.org\n")
        buffer.writeString("\n")
        buffer.writeInteger(UInt8(0))

        let frame = try #require(try decoder.decode(buffer: &buffer))
        #expect(frame.command == .connect)
        #expect(frame.headers.count == 2)
        #expect(frame.headers[0] == STOMPHeader(name: .acceptVersion, value: "1.2"))
        #expect(frame.headers[1] == STOMPHeader(name: .host, value: "stomp.github.org"))
        #expect(frame.body.readableBytes == 0)
    }

    @Test("Decode Frame with Content Length")
    func decodeFrameWithContentLength() throws {
        let decoder = STOMPFrameDecoder()

        var buffer = ByteBufferAllocator().buffer(capacity: 64)
        buffer.writeString("SEND\n")
        buffer.writeString("content-length:5\n")
        buffer.writeString("\n")
        buffer.writeString("hello")
        buffer.writeInteger(UInt8(0))

        let frame = try #require(try decoder.decode(buffer: &buffer))
        #expect(frame.command == .send)
        #expect(frame.headers.contains(where: { $0.name == .contentLength && $0.value == "5" }))
        #expect(frame.body.getString(at: frame.body.readerIndex, length: frame.body.readableBytes) == "hello")
    }

    @Test("Decode Frame until NULL without Content Length")
    func decodeFrameUntilNullWithoutContentLength() throws {
        let decoder = STOMPFrameDecoder()

        var buffer = ByteBufferAllocator().buffer(capacity: 64)
        buffer.writeString("MESSAGE\n\n")
        buffer.writeString("he")
        buffer.writeInteger(UInt8(0))
        buffer.writeString("llo")  // should belong to next frame or trailing garbage, not in body

        let frame = try #require(try decoder.decode(buffer: &buffer))
        #expect(frame.command == .message)
        #expect(frame.body.getString(at: frame.body.readerIndex, length: frame.body.readableBytes) == "he")
    }

    @Test("Ignore leading EOL heartbeats before frame")
    func ignoreLeadingEOLHeartbeats() throws {
        let decoder = STOMPFrameDecoder()

        var buffer = ByteBufferAllocator().buffer(capacity: 64)
        buffer.writeString("\n\n")  // heartbeats
        buffer.writeString("CONNECT\n")
        buffer.writeString("accept-version:1.2\n")
        buffer.writeString("\n")
        buffer.writeInteger(UInt8(0))

        let frame = try #require(try decoder.decode(buffer: &buffer))
        #expect(frame.command == .connect)
        #expect(frame.headers.contains(where: { $0.name == .acceptVersion && $0.value == "1.2" }))
    }

    @Test("Consume trailing EOLs after NULL terminator")
    func consumeTrailingEOLsAfterNull() throws {
        let decoder = STOMPFrameDecoder()

        var buffer = ByteBufferAllocator().buffer(capacity: 64)
        buffer.writeString("SEND\n\n")
        buffer.writeString("payload")
        buffer.writeInteger(UInt8(0))
        buffer.writeString("\n\n\r\n")  // trailing EOLs to be skipped

        let frame = try #require(try decoder.decode(buffer: &buffer))
        #expect(frame.command == .send)
        #expect(frame.body.getString(at: frame.body.readerIndex, length: frame.body.readableBytes) == "payload")
        // After decode, trailing EOLs should have been consumed; decoder leaves readerIndex at next frame
        #expect(buffer.readableBytes == 0)
    }
}
