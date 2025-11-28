import Foundation
import NIOCore

struct STOMPFrameDecoder: NIOSingleStepByteToMessageDecoder {
    typealias InboundOut = STOMPFrame

    func decode(buffer: inout ByteBuffer) throws -> STOMPFrame? {
        let originalReaderIndex = buffer.readerIndex

        // Helper to reset and return nil when more data is needed
        func needMoreData() -> STOMPFrame? {
            buffer.moveReaderIndex(to: originalReaderIndex)
            return nil
        }

        // Skip any leading heart-beat EOLs (LF or CRLF) that may appear between frames
        skipEOLs(&buffer)

        // 1) Read command line (terminated by EOL = [CR] LF)
        guard let commandLine = readLine(&buffer) else {
            return needMoreData()
        }
        guard let command = STOMPCommand(rawValue: commandLine) else {
            throw ParseError.invalidCommand(commandLine)
        }

        // 2) Read headers until empty line
        var headers: [STOMPHeader] = []
        var contentLength: Int? = nil

        while true {
            guard let line = readLine(&buffer) else { return needMoreData() }
            if line.isEmpty { break }  // empty line separates headers and body

            guard let colonIndex = line.firstIndex(of: ":") else {
                throw ParseError.malformedHeader(line)
            }
            let name = String(line[..<colonIndex])
            let valueStart = line.index(after: colonIndex)
            let value = String(line[valueStart...])

            headers.append(STOMPHeader(name: name, value: value))

            if contentLength == nil && name.caseInsensitiveCompare("content-length") == .orderedSame {
                guard let len = Int(value.trimmingCharacters(in: .whitespaces)) else {
                    throw ParseError.invalidContentLength(value)
                }
                if len < 0 { throw ParseError.invalidContentLength(value) }
                contentLength = len
            }
        }

        // 3) Read body and the required NULL terminator
        let body: ByteBuffer
        if let len = contentLength {
            // Need exactly 'len' octets for body plus one NULL
            guard buffer.readableBytes >= len + 1 else { return needMoreData() }
            guard let slice = buffer.readSlice(length: len) else { return needMoreData() }
            body = slice
            // Expect NULL terminator
            guard let nullByte: UInt8 = buffer.readInteger(), nullByte == 0 else {
                throw ParseError.missingNullTerminator
            }
        } else {
            // Body until first NULL octet (0x00)
            guard let relNullIndex = buffer.readableBytesView.firstIndex(of: 0) else {
                return needMoreData()
            }
            let bodyLen = buffer.readableBytesView.distance(from: buffer.readableBytesView.startIndex, to: relNullIndex)
            guard let slice = buffer.readSlice(length: bodyLen) else { return needMoreData() }
            body = slice
            // Consume NULL terminator
            _ = buffer.readInteger(as: UInt8.self)
        }

        // 4) Consume any trailing EOLs after NULL (heartbeat spacing between frames)
        skipEOLs(&buffer)

        return STOMPFrame(command: command, headers: headers, body: body)
    }

    func decodeLast(buffer: inout ByteBuffer, seenEOF _: Bool) throws -> STOMPFrame? {
        try self.decode(buffer: &buffer)
    }

    // MARK: - Helpers

    internal enum ParseError: Error, CustomStringConvertible {
        case invalidCommand(String)
        case malformedHeader(String)
        case invalidContentLength(String)
        case missingNullTerminator

        var description: String {
            switch self {
            case .invalidCommand(let cmd): return "Invalid STOMP command: \(cmd)"
            case .malformedHeader(let line): return "Malformed header line: \(line)"
            case .invalidContentLength(let v): return "Invalid content-length: \(v)"
            case .missingNullTerminator: return "Missing NULL terminator after body"
            }
        }
    }

    // Read a line terminated by EOL = [CR] LF. Returns the line content without CR/LF.
    private func readLine(_ buffer: inout ByteBuffer) -> String? {
        // Find LF in the readable view
        guard let lfIndex = buffer.readableBytesView.firstIndex(of: 10) else { return nil }
        let lengthToLF = buffer.readableBytesView.distance(from: buffer.readableBytesView.startIndex, to: lfIndex)

        // Peek if preceding byte is CR
        let hasCR: Bool
        if lengthToLF > 0, let byteBeforeLF: UInt8 = buffer.getInteger(at: buffer.readerIndex + lengthToLF - 1, as: UInt8.self) {
            hasCR = (byteBeforeLF == 13)
        } else {
            hasCR = false
        }

        // Read bytes up to and including LF
        guard var lineSlice = buffer.readSlice(length: lengthToLF + 1) else { return nil }
        // Drop LF
        lineSlice.moveWriterIndex(to: lineSlice.writerIndex - 1)
        // Drop optional CR (now last char if present)
        if hasCR {
            lineSlice.moveWriterIndex(to: lineSlice.writerIndex - 1)
        }
        return lineSlice.readString(length: lineSlice.readableBytes) ?? ""
    }

    // Consume zero or more EOLs (LF or CRLF)
    private func skipEOLs(_ buffer: inout ByteBuffer) {
        while buffer.readableBytes > 0 {
            if let first: UInt8 = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) {
                if first == 10 {  // LF
                    _ = buffer.readInteger(as: UInt8.self)
                    continue
                }
                if first == 13 {  // CR
                    if let second: UInt8 = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self), second == 10 {
                        _ = buffer.readInteger(as: UInt8.self)
                        _ = buffer.readInteger(as: UInt8.self)
                        continue
                    } else {
                        // Consume solitary CR defensively
                        _ = buffer.readInteger(as: UInt8.self)
                        continue
                    }
                }
            }
            break
        }
    }
}
