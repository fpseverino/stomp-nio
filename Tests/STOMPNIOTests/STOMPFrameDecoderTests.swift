import NIOCore
import Testing

@testable import STOMPNIO

@Suite("STOMPFrameDecoder Tests")
struct STOMPFrameDecoderTests {
    let decoder = STOMPFrameDecoder()

    @Test("Decode simple CONNECT Frame")
    func decodeSimpleConnectFrame() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            CONNECT
            accept-version:1.2
            host:stomp.github.org

            \u{0}
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .connect)
        #expect(frame.headers.count == 2)
        #expect(frame.headers[0] == STOMPHeader(name: .acceptVersion, value: "1.2"))
        #expect(frame.headers[1] == STOMPHeader(name: .host, value: "stomp.github.org"))
        #expect(frame.body.readableBytes == 0)
    }

    @Test("Decode 1.2 Frame with Carriage Return")
    func decodeFrameWithCarriageReturn() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            CONNECT\r
            accept-version:1.2\r
            host:stomp.github.org\r
            \r
            \u{0}
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .connect)
        #expect(frame.headers.count == 2)
        #expect(frame.headers[0] == STOMPHeader(name: .acceptVersion, value: "1.2"))
        #expect(frame.headers[1] == STOMPHeader(name: .host, value: "stomp.github.org"))
        #expect(frame.body.readableBytes == 0)
    }

    @Test("Decode Last Frame")
    func decodeLastFrame() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            DISCONNECT

            \u{0}
            """
        )

        let frame = try #require(try self.decoder.decodeLast(buffer: &buffer, seenEOF: false))
        #expect(frame.command == .disconnect)
        #expect(frame.headers.isEmpty)
        #expect(frame.body.readableBytes == 0)
    }

    @Test("Decode Frame without Empty Line between Headers and Body")
    func decodeFrameWithoutEmptyLineBetweenHeadersAndBody() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND
            destination:/queue/a
            content-type:text/plain
            content-length:11
            hello world\u{0}
            """
        )

        #expect(try self.decoder.decode(buffer: &buffer) == nil)  // Need more data
    }

    @Test("Decode Generic Headers with Padding")
    func decodeHeadersWithPadding() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            CONNECT
            accept-version: 1.2
            host:           stomp.github.org

            \u{0}
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .connect)
        #expect(frame.headers.count == 2)
        // In STOMP 1.1 and 1.2, clients and servers MUST never trim or pad headers with spaces.
        #expect(frame.headers[0] == STOMPHeader(name: .acceptVersion, value: " 1.2"))
        #expect(frame.headers[1] == STOMPHeader(name: .host, value: "           stomp.github.org"))
        #expect(frame.body.readableBytes == 0)
    }

    @Test("Decode Content Length Header with Padding")
    func decodeContentLengthHeaderWithPadding() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND
            content-length: 6

            hello
            \u{0}
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .send)
        // The value preserves the padding, but for the purposes of `content-length` parsing we trim it.
        #expect(frame.headers.contains(where: { $0.name == .contentLength && $0.value == " 6" }))
        #expect(frame.body.getString(at: frame.body.readerIndex, length: frame.body.readableBytes) == "hello\n")
    }

    @Test("Decode Frame with Content Length")
    func decodeFrameWithContentLength() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND
            content-length:5

            hello\u{0}
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .send)
        #expect(frame.headers.contains(where: { $0.name == .contentLength && $0.value == "5" }))
        #expect(frame.body.getString(at: frame.body.readerIndex, length: frame.body.readableBytes) == "hello")
    }

    @Test("Decode Frame with Negative Content Length")
    func decodeFrameWithNegativeContentLength() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND
            content-length:-5

            hello\u{0}
            """
        )

        #expect(throws: STOMPFrameDecoder.ParseError.invalidContentLength("-5")) { try self.decoder.decode(buffer: &buffer) }
    }

    @Test("Decode Frame with Zero Content Length")
    func decodeFrameWithZeroContentLength() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND
            content-length:0

            \u{0}
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .send)
        #expect(frame.headers.contains(where: { $0.name == .contentLength && $0.value == "0" }))
        #expect(frame.body.readableBytes == 0)
    }

    @Test("Decode Frame with Content Length and NULL octet in body")
    func decodeFrameWithContentLengthAndNullOctetInBody() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND
            content-length:11

            hello\u{0}world\u{0}
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .send)
        #expect(frame.headers.contains(where: { $0.name == .contentLength && $0.value == "11" }))
        #expect(frame.body.getString(at: frame.body.readerIndex, length: frame.body.readableBytes) == "hello\u{0}world")
    }

    @Test("Decode Frame until NULL without Content Length")
    func decodeFrameUntilNullWithoutContentLength() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            MESSAGE

            he\u{0}llo
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .message)
        #expect(frame.body.getString(at: frame.body.readerIndex, length: frame.body.readableBytes) == "he")
    }

    @Test("Decode Frame with Shorter Body than Content Length")
    func decodeFrameWithShorterBodyThanContentLength() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND
            content-length:10

            hello\u{0}
            """
        )

        #expect(try self.decoder.decode(buffer: &buffer) == nil)  // Need more data
    }

    @Test("Decode Frame with Content Length longer than Body before NULL")
    func decodeFrameWithContentLengthLongerThanBodyBeforeNull() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND
            content-length:5

            Hello, World!\u{0}
            """
        )

        #expect(throws: STOMPFrameDecoder.ParseError.missingNullTerminator) { try self.decoder.decode(buffer: &buffer) }
    }

    @Test("Ignore leading EOL heartbeats before frame")
    func ignoreLeadingEOLHeartbeats() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            \n\r\nCONNECT
            accept-version:1.2

            \u{0}
            """
        )
        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .connect)
        #expect(frame.headers.contains(where: { $0.name == .acceptVersion && $0.value == "1.2" }))
    }

    @Test("Consume trailing EOLs after NULL terminator")
    func consumeTrailingEOLsAfterNull() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND

            payload\u{0}\n\n\r\n
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .send)
        #expect(frame.body.getString(at: frame.body.readerIndex, length: frame.body.readableBytes) == "payload")
        // After decode, trailing EOLs should have been consumed; decoder leaves readerIndex at next frame
        #expect(buffer.readableBytes == 0)
    }

    @Test("Consume Solitary CR")
    func consumeSolitaryCR() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            \r\r
            SEND

            payload\u{0}\r\r
            """
        )

        let frame = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame.command == .send)
        #expect(frame.body.getString(at: frame.body.readerIndex, length: frame.body.readableBytes) == "payload")
        // After decode, solitary CR should have been consumed; decoder leaves readerIndex at next frame
        #expect(buffer.readableBytes == 0)
    }

    @Test("Decode Two Frames with EOL Heartbeats in Between")
    func decodeTwoFramesWithEOLHeartbeatsInBetween() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            CONNECT
            accept-version:1.2

            \u{0}
            \n\r\n\n\n\r\n\r
            SEND
            destination:/queue/a
            content-length:5

            hello\u{0}
            """
        )

        let frame1 = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame1.command == .connect)
        #expect(frame1.headers.contains(where: { $0.name == .acceptVersion && $0.value == "1.2" }))
        #expect(buffer.readableBytes > 0)

        let frame2 = try #require(try self.decoder.decode(buffer: &buffer))
        #expect(frame2.command == .send)
        #expect(frame2.headers.contains(where: { $0.name == .contentLength && $0.value == "5" }))
        #expect(frame2.body.getString(at: frame2.body.readerIndex, length: frame2.body.readableBytes) == "hello")
        #expect(buffer.readableBytes == 0)
    }

    @Test("Decode Frame with Non-Existent Command")
    func decodeFrameWithNonExistentCommand() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            NONEXISTENT
            header1:value1

            body\u{0}
            """
        )

        #expect(throws: STOMPFrameDecoder.ParseError.invalidCommand("NONEXISTENT")) { try self.decoder.decode(buffer: &buffer) }
    }

    @Test("Decode Frame with Incomplete Command Line")
    func decodeFrameWithIncompleteCommandLine() throws {
        var buffer = ByteBuffer()
        buffer.writeString("CONNE")
        #expect(try self.decoder.decode(buffer: &buffer) == nil)  // Need more data
    }

    @Test("Decode Frame with Malformed Header")
    func decodeFrameWithMalformedHeader() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            CONNECT
            malformed-header-without-colon

            \u{0}
            """
        )

        #expect(throws: STOMPFrameDecoder.ParseError.malformedHeader("malformed-header-without-colon")) {
            try self.decoder.decode(buffer: &buffer)
        }
    }

    @Test("Decode Frame Missing NULL Terminator and Content Length")
    func decodeFrameMissingNullTerminatorAndContentLength() throws {
        var buffer = ByteBuffer()
        buffer.writeString(
            """
            SEND

            body without null terminator
            """
        )

        #expect(try self.decoder.decode(buffer: &buffer) == nil)  // Need more data
    }
}
