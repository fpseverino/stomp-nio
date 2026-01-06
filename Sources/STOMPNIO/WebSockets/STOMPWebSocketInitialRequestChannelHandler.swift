import NIOCore
import NIOHTTP1

/// The HTTP handler to be used to initiate the request.
///
/// This initial request will be adapted by the WebSocket upgrader to contain the upgrade header parameters.
/// `channelRead` will only be called if the upgrade fails.
final class STOMPWebSocketInitialRequestChannelHandler: ChannelInboundHandler, RemovableChannelHandler, Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    let host: String
    let urlPath: String
    let additionalHeaders: HTTPHeaders
    let upgradePromise: EventLoopPromise<Void>

    init(host: String, urlPath: String, additionalHeaders: HTTPHeaders, upgradePromise: EventLoopPromise<Void>) {
        self.host = host
        self.urlPath = urlPath
        self.additionalHeaders = additionalHeaders
        self.upgradePromise = upgradePromise
    }

    func channelActive(context: ChannelHandlerContext) {
        // We are connected. It's time to send the message to the server to initialize the upgrade dance.
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "0")
        headers.add(name: "host", value: self.host)
        headers.add(name: "Sec-WebSocket-Protocol", value: "v12.stomp, v11.stomp, v10.stomp")
        headers.add(contentsOf: self.additionalHeaders)

        let requestHead = HTTPRequestHead(
            version: HTTPVersion(major: 1, minor: 1),
            method: .GET,
            uri: self.urlPath,
            headers: headers
        )

        context.write(self.wrapOutboundOut(.head(requestHead)), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(ByteBuffer()))), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }

    /// This will be called only if the WebSocket upgrade fails.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let clientResponse = self.unwrapInboundIn(data)

        switch clientResponse {
        case .head:
            self.upgradePromise.fail(STOMPClientError.websocketUpgradeFailed)
        case .body:
            break
        case .end:
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        self.upgradePromise.fail(error)
        // As we are not really interested in getting notified on success or failure,
        // we just pass `nil` as the promise to reduce allocations.
        context.close(promise: nil)
    }
}
