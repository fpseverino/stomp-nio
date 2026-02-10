import NIOCore
import NIOEmbedded
import NIOHTTP1
import Testing

@testable import STOMPNIO

@Suite("STOMP NIO Core Tests")
struct STOMPNIOCoreTests {
    @Test("STOMP Command String Representation")
    func stompCommandStringRepresentation() {
        let command = STOMPFrame.Command.connect
        #expect(command.description == "CONNECT")

        let parsedCommand = STOMPFrame.Command("SEND")
        #expect(parsedCommand == .send)

        let invalidCommand = STOMPFrame.Command("INVALID")
        #expect(invalidCommand == nil)
    }

    @Suite("Headers Tests")
    struct HeadersTests {
        @Test("Header Name", arguments: STOMPHeader.Name.allCases)
        func headerName(name: STOMPHeader.Name) {
            let nameDescription = name.description
            #expect(nameDescription == name.playgroundDescription as? String)

            let reconstructedName = STOMPHeader.Name(nameDescription)
            #expect(reconstructedName == name)

            let headerValue = "test-value"
            let header = STOMPHeader(name: nameDescription, value: headerValue)
            #expect(header.name == name)
            #expect(header.value == headerValue)
            #expect(header.description == "\(nameDescription):\(headerValue)")
            #expect(header.playgroundDescription as? String == header.description)
        }

        @Test("Headers Collection")
        func headersCollection() {
            var headers: STOMPHeaders = [
                STOMPHeader(name: .destination, value: "/queue/test"),
                STOMPHeader(name: .contentType, value: "text/plain"),
                STOMPHeader(name: .destination, value: "/queue/another"),
            ]

            #expect(headers.contains(.destination))
            #expect(!headers.contains(.ack))

            #expect(headers[.contentType] == "text/plain")
            #expect(headers[.ack] == nil)

            let destinationValues = headers[values: .destination]
            #expect(destinationValues == ["/queue/test", "/queue/another"])

            let destinationHeaders = headers[headers: .destination]
            #expect(destinationHeaders.count == 2)
            #expect(destinationHeaders[0].value == "/queue/test")
            #expect(destinationHeaders[1].value == "/queue/another")

            headers[1] = STOMPHeader(name: .ack, value: "auto")
            #expect(headers.contains(.ack))
            #expect(headers.headers.count == 3)
        }
    }

    @Test("Start of Whitespace Suffix in All-Whitespace String")
    func startOfWhitespaceSuffixInAllWhitespaceString() {
        let string = "     "
        let index = string.startOfWhitespaceSuffix()
        #expect(index == string.startIndex)
    }

    @Test("WebSocket Initial Request")
    func webSocketInitialRequest() throws {
        let el = EmbeddedEventLoop()
        defer { #expect(throws: Never.self) { try el.syncShutdownGracefully() } }
        let promise = el.makePromise(of: Void.self)
        let initialRequestHandler = STOMPWebSocketInitialRequestChannelHandler(
            host: "example.com",
            urlPath: "/stomp",
            additionalHeaders: ["Test": "Value"],
            upgradePromise: promise
        )
        let channel = EmbeddedChannel(handler: initialRequestHandler, loop: el)
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
        let requestHead = try channel.readOutbound(as: HTTPClientRequestPart.self)
        let requestBody = try channel.readOutbound(as: HTTPClientRequestPart.self)
        let requestEnd = try channel.readOutbound(as: HTTPClientRequestPart.self)
        switch requestHead {
        case .head(let head):
            #expect(head.uri == "/stomp")
            #expect(head.headers["host"].first == "example.com")
            #expect(head.headers["Sec-WebSocket-Protocol"].first == "v12.stomp, v11.stomp, v10.stomp")
            #expect(head.headers["Test"].first == "Value")
        default:
            Issue.record("Unexpected request head: \(String(describing: requestHead))")
        }
        switch requestBody {
        case .body(let data):
            #expect(data == .byteBuffer(ByteBuffer()))
        default:
            Issue.record("Unexpected request body: \(String(describing: requestBody))")
        }
        switch requestEnd {
        case .end(nil):
            break
        default:
            Issue.record("Unexpected request end: \(String(describing: requestEnd))")
        }
        _ = try channel.finish()
        promise.succeed(())
    }
}

extension STOMPHeader.Name: CaseIterable {
    static var allCases: [STOMPHeader.Name] {
        [
            .contentLength,
            .contentType,
            .receipt,
            .acceptVersion,
            .host,
            .login,
            .passcode,
            .heartBeat,
            .version,
            .session,
            .server,
            .destination,
            .transaction,
            .id,
            .ack,
            .messageID,
            .subscription,
            .receiptID,
            .message,
            .selector,
        ]
    }
}
