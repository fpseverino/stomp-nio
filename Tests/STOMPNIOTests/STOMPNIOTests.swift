import Testing

@testable import STOMPNIO

@Suite("STOMP NIO Tests")
struct STOMPNIOTests {
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

    @Test("Start of Whitespace Suffix in All-Whitespace Substring")
    func startOfWhitespaceSuffixInAllWhitespaceSubstring() {
        let substring: Substring = "     "
        let index = substring.startOfWhitespaceSuffix()
        #expect(index == substring.startIndex)
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
