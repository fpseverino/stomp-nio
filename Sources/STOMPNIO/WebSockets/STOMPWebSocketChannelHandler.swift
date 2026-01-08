import NIOCore
import NIOWebSocket
import Synchronization

/// WebSocket channel handler.
/// Sends WebSocket frames, receives and combines frames.
///
/// Code inspired from [`vapor/websocket-kit`](https://github.com/vapor/websocket-kit)
/// and the [WebSocket sample from `swift-nio`](https://github.com/apple/swift-nio/tree/main/Sources/NIOWebSocketClient)
final class STOMPWebSocketChannelHandler: ChannelDuplexHandler {
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = WebSocketFrame
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = ByteBuffer

    private var webSocketFrameSequence: WebSocketFrameSequence?

    private let isClosed: Atomic<Bool> = .init(false)

    /// Write `ByteBuffer`s as a WebSocket frame
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard context.channel.isActive else { return }

        let buffer = unwrapOutboundIn(data)
        self.send(context: context, buffer: buffer, opcode: .binary, fin: true, promise: promise)
    }

    /// Read WebSocket frame
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)

        switch frame.opcode {
        case .text, .binary:
            if var frameSeq = self.webSocketFrameSequence {
                frameSeq.append(frame)
                self.webSocketFrameSequence = frameSeq
            } else {
                var frameSeq = WebSocketFrameSequence(type: frame.opcode)
                frameSeq.append(frame)
                self.webSocketFrameSequence = frameSeq
            }
        case .continuation:
            if var frameSeq = self.webSocketFrameSequence {
                frameSeq.append(frame)
                self.webSocketFrameSequence = frameSeq
            } else {
                self.close(context: context, code: .protocolError, promise: nil)
            }
        case .connectionClose:
            self.receivedClose(context: context)
        default:
            break
        }

        if let frameSeq = self.webSocketFrameSequence, frame.fin {
            switch frameSeq.type {
            case .binary, .text:
                context.fireChannelRead(wrapInboundOut(frameSeq.buffer))
            default: break
            }
            self.webSocketFrameSequence = nil
        }
    }

    /// Send WebSocket frame to server
    private func send(
        context: ChannelHandlerContext,
        buffer: ByteBuffer,
        opcode: WebSocketOpcode,
        fin: Bool = true,
        promise: EventLoopPromise<Void>? = nil
    ) {
        let maskKey = self.makeMaskKey()
        let frame = WebSocketFrame(fin: fin, opcode: opcode, maskKey: maskKey, data: buffer)
        context.writeAndFlush(wrapOutboundOut(frame), promise: promise)
    }

    private func receivedClose(context: ChannelHandlerContext) {
        // Handle a received close frame. We're just going to close.
        self.isClosed.store(true, ordering: .relaxed)
        context.close(promise: nil)
    }

    /// Make mask key to be used in WebSocket frame
    func makeMaskKey() -> WebSocketMaskingKey? {
        let bytes: [UInt8] = (0..<4).map { _ in UInt8.random(in: .min ... .max) }
        return WebSocketMaskingKey(bytes)
    }

    /// Close WebSocket connection
    func close(context: ChannelHandlerContext, code: WebSocketErrorCode = .goingAway, promise: EventLoopPromise<Void>?) {
        guard self.isClosed.compareExchange(expected: false, desired: true, successOrdering: .relaxed, failureOrdering: .relaxed).exchanged
        else {
            promise?.succeed(())
            return
        }

        let codeAsInt = UInt16(webSocketErrorCode: code)
        let codeToSend: WebSocketErrorCode
        if codeAsInt == 1005 || codeAsInt == 1006 {
            // Code `1005` and `1006` are used to report errors to the application,
            // but must never be sent over the wire (per https://tools.ietf.org/html/rfc6455#section-7.4)
            codeToSend = .normalClosure
        } else {
            codeToSend = code
        }

        var buffer = context.channel.allocator.buffer(capacity: 2)
        buffer.write(webSocketErrorCode: codeToSend)
        self.send(context: context, buffer: buffer, opcode: .connectionClose, fin: true, promise: promise)
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.close(context: context, code: .unknown(1006), promise: nil)

        // We always forward the error on to let others see it.
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        let errorCode: WebSocketErrorCode
        if let error = error as? NIOWebSocketError {
            errorCode = WebSocketErrorCode(error)
        } else {
            errorCode = .unexpectedServerError
        }
        self.close(context: context, code: errorCode, promise: nil)

        // We always forward the error on to let others see it.
        context.fireErrorCaught(error)
    }
}

private struct WebSocketFrameSequence {
    var buffer: ByteBuffer
    var type: WebSocketOpcode

    init(type: WebSocketOpcode) {
        self.buffer = ByteBufferAllocator().buffer(capacity: 0)
        self.type = type
    }

    mutating func append(_ frame: WebSocketFrame) {
        var data = frame.unmaskedData
        switch self.type {
        case .binary, .text:
            self.buffer.writeBuffer(&data)
        default: break
        }
    }
}

extension WebSocketErrorCode {
    fileprivate init(_ error: NIOWebSocketError) {
        switch error {
        case .invalidFrameLength:
            self = .messageTooLarge
        case .fragmentedControlFrame,
            .multiByteControlFrameLength:
            self = .protocolError
        }
    }
}
