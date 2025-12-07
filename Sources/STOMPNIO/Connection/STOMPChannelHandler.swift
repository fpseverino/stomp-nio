import Logging
public import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@usableFromInline
final class STOMPChannelHandler: ChannelDuplexHandler {
    @usableFromInline
    struct Configuration {
        let authentication: STOMPConnectionConfiguration.Authentication?
        let virtualHost: String?
        @usableFromInline
        let connectTimeout: TimeAmount
        @usableFromInline
        let receiptTimeout: TimeAmount
    }

    struct STOMPDeadlineSchedule: NIOScheduledCallbackHandler {
        let channelHandler: NIOLoopBound<STOMPChannelHandler>

        func handleScheduledCallback(eventLoop: some NIOCore.EventLoop) {
            let channelHandler = self.channelHandler.value
            switch channelHandler.stateMachine.hitDeadline(now: .now()) {
            case .failTasksAndClose(let context, let commands):
                let error = STOMPClientError.timeout
                for command in commands {
                    command.promise.fail(error)
                }
                channelHandler.failTasksAndCloseSubscriptions(with: error)
                context.fireErrorCaught(error)
                context.close(promise: nil)
            case .reschedule(let deadline):
                channelHandler.scheduleDeadlineCallback(deadline: deadline)
            case .clearCallback:
                channelHandler.deadlineCallback = nil
                break
            }
        }
    }

    @usableFromInline
    typealias InboundIn = ByteBuffer
    @usableFromInline
    typealias InboundOut = STOMPFrame
    @usableFromInline
    typealias OutboundIn = STOMPFrame
    @usableFromInline
    typealias OutboundOut = ByteBuffer

    @usableFromInline
    let eventLoop: any EventLoop
    @usableFromInline
    var stateMachine: StateMachine<ChannelHandlerContext>
    @usableFromInline
    var subscriptions: STOMPSubscriptions

    @usableFromInline
    private(set) var deadlineCallback: NIOScheduledCallback?

    private var decoder: NIOSingleStepByteToMessageProcessor<STOMPFrameDecoder>
    private let logger: Logger
    @usableFromInline
    let configuration: Configuration

    init(configuration: Configuration, eventLoop: any EventLoop, logger: Logger) {
        self.configuration = configuration
        self.eventLoop = eventLoop
        self.subscriptions = STOMPSubscriptions(logger: logger)
        self.decoder = NIOSingleStepByteToMessageProcessor(STOMPFrameDecoder())
        self.stateMachine = .init()
        self.logger = logger
    }

    @usableFromInline
    func setInitialized(context: ChannelHandlerContext) {
        var headers: [STOMPHeader] = [STOMPHeader(name: "accept-version", value: "1.0,1.1,1.2")]
        if let authentication = self.configuration.authentication {
            headers.append(STOMPHeader(name: "login", value: authentication.login))
            headers.append(STOMPHeader(name: "passcode", value: authentication.passcode))
        }
        if let virtualHost = self.configuration.virtualHost {
            headers.append(STOMPHeader(name: "host", value: virtualHost))
        }
        let connectFrame = STOMPFrame(command: .connect, headers: headers)

        var buffer = context.channel.allocator.buffer(capacity: 128)
        connectFrame.encode(into: &buffer)

        let promise = self.eventLoop.makePromise(of: STOMPFrame.self)

        let deadline = .now() + self.configuration.connectTimeout
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
        self.scheduleDeadlineCallback(deadline: deadline)

        self.stateMachine.setInitialized(
            context: context,
            connectTask: .init(promise: .nio(promise), deadline: deadline) { $0.command == .connected }
        )
    }

    @usableFromInline
    func waitOnConnected() -> EventLoopFuture<Void> {
        switch self.stateMachine.waitOnConnected() {
        case .waitForPromise(let promise):
            return promise.futureResult.map { _ in return }
        case .reportedClosed(let error):
            return self.eventLoop.makeFailedFuture(error ?? STOMPClientError.connectionClosed)
        case .done:
            return self.eventLoop.makeSucceededVoidFuture()
        }
    }

    @usableFromInline
    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            self.setInitialized(context: context)
            self.logger.trace("STOMPChannelHandler added when channel is active.")
        }
    }

    @usableFromInline
    func channelActive(context: ChannelHandlerContext) {
        self.setInitialized(context: context)
        self.logger.trace("Channel active.")
        context.fireChannelActive()
    }

    @usableFromInline
    func channelInactive(context: ChannelHandlerContext) {
        // channel is inactive so we should fail all tasks in progress
        self.failTasksAndCloseSubscriptions(with: STOMPClientError.connectionClosed)
        self.logger.trace("Channel inactive.")
        context.fireChannelInactive()
    }

    @usableFromInline
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        // we caught an error so we should fail all active tasks
        self.failTasksAndCloseSubscriptions(with: error)
    }

    @usableFromInline
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let frame = self.unwrapOutboundIn(data)
        self.logger.trace("Sending STOMP message: \(frame.command.rawValue)")
        var buffer = context.channel.allocator.buffer(capacity: 128)
        frame.encode(into: &buffer)
        context.write(self.wrapOutboundOut(buffer), promise: promise)
    }

    @usableFromInline
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        do {
            try self.decoder.process(buffer: buffer) { frame in
                self.handleFrame(context: context, frame: frame)
            }
        } catch let error as STOMPFrameDecoder.ParseError {
            self.logger.debug("STOMPChannelHandler: ERROR", metadata: ["error": "\(error)"])

            self.failTasksAndCloseSubscriptions(with: error)
            context.fireErrorCaught(error)
            context.close(promise: nil)
        } catch {
            preconditionFailure("Expected to only get ParseError from the STOMPFrameDecoder.")
        }
    }

    func handleFrame(context: ChannelHandlerContext, frame: STOMPFrame) {
        self.logger.trace("Received STOMP message: \(frame.command.rawValue)")

        switch self.stateMachine.receivedFrame(frame) {
        case .succeedTask(let task, let deadlineAction):
            self.processDeadlineCallbackAction(action: deadlineAction)
            task.promise.succeed(frame)
        case .failTask(let task, let error):
            task.promise.fail(error)
        case .unhandledTask:
            break
        case .messageReceived:
            let ackHeader = frame.headers.first(where: { $0.name == "ack" }).map { STOMPHeader(name: "id", value: $0.value) }
            do {
                try self.subscriptions.notify(frame)

                guard let subscriptionHeader = frame.headers.first(where: { $0.name == "subscription" }),
                    let messageIDHeader = frame.headers.first(where: { $0.name == "message-id" })
                else {
                    throw STOMPClientError.missingHeader(message: "Missing subscription or message-id header in MESSAGE frame")
                }
                if let subscriptionID = Int(subscriptionHeader.value), self.subscriptions.shouldAcknowledge(id: subscriptionID) {
                    var headers = [
                        STOMPHeader(name: "subscription", value: subscriptionHeader.value),
                        STOMPHeader(name: "message-id", value: messageIDHeader.value),
                    ]
                    if let ackHeader { headers.append(ackHeader) }
                    let ackFrame = STOMPFrame(
                        command: .ack,
                        headers: headers
                    )
                    _ = context.channel.writeAndFlush(ackFrame)
                }
            } catch {
                self.failTasksAndCloseSubscriptions(with: error)
                context.fireErrorCaught(error)
                context.close(promise: nil)
            }
        case .closeConnection(let error):
            self.failTasksAndCloseSubscriptions(with: error)
            context.fireErrorCaught(error)
            context.close(promise: nil)
        }
    }

    @usableFromInline
    func scheduleDeadlineCallback(deadline: NIODeadline) {
        self.deadlineCallback = try? self.eventLoop.scheduleCallback(
            at: deadline,
            handler: STOMPDeadlineSchedule(channelHandler: .init(self, eventLoop: self.eventLoop))
        )
    }

    func processDeadlineCallbackAction(action: StateMachine<ChannelHandlerContext>.DeadlineCallbackAction) {
        switch action {
        case .cancel:
            self.deadlineCallback?.cancel()
            self.deadlineCallback = nil
        case .reschedule(let deadline):
            self.scheduleDeadlineCallback(deadline: deadline)
        case .doNothing:
            break
        }
    }

    private func failTasksAndCloseSubscriptions(with error: any Error) {
        switch self.stateMachine.close() {
        case .failTasksAndClose(let tasks):
            for task in tasks {
                task.promise.fail(error)
            }
            self.subscriptions.close(error: error)
            self.deadlineCallback?.cancel()
        case .doNothing:
            break
        }
    }

    func triggerGracefulShutdown() {
        switch self.stateMachine.triggerGracefulShutdown() {
        case .closeConnection(let context):
            context.close(mode: .all, promise: nil)
        case .doNothing:
            break
        }
    }

    @usableFromInline
    func sendFrame(
        _ frame: STOMPFrame,
        promise: STOMPPromise<STOMPFrame>,
        checkInbound: @escaping @Sendable (STOMPFrame) throws -> Bool
    ) {
        self.eventLoop.assertInEventLoop()
        let deadline = .now() + self.configuration.receiptTimeout
        let task = STOMPTask(promise: promise, deadline: deadline, checkInbound: checkInbound)
        switch self.stateMachine.sendFrame(task) {
        case .sendFrame(let context):
            _ = context.channel.writeAndFlush(frame)
            if self.deadlineCallback == nil {
                self.scheduleDeadlineCallback(deadline: deadline)
            }
        case .throwError(let error):
            task.promise.fail(error)
        }
    }

    private func sendFrame(
        _ frame: STOMPFrame,
        checkInbound: @escaping @Sendable (STOMPFrame) throws -> Bool
    ) -> EventLoopFuture<STOMPFrame> {
        let promise = self.eventLoop.makePromise(of: STOMPFrame.self)
        self.sendFrame(frame, promise: .nio(promise), checkInbound: checkInbound)
        return promise.futureResult
    }

    func subscribe(
        streamContinuation: STOMPSubscription.Continuation,
        destination: String,
        ackMode: STOMPAckMode,
        userDefinedHeaders: [STOMPHeader],
        promise: STOMPPromise<Int>
    ) {
        self.eventLoop.assertInEventLoop()
        switch self.subscriptions.addSubscription(continuation: streamContinuation, destination: destination, ackMode: ackMode) {
        case .subscribe(let subscription, _):
            let subscriptionID = subscription.id
            let receiptID = UUID().uuidString
            let subscribeFrame = STOMPFrame(
                command: .subscribe,
                headers: [
                    STOMPHeader(name: "destination", value: destination),
                    STOMPHeader(name: "id", value: String(subscriptionID)),
                    STOMPHeader(name: "ack", value: ackMode.rawValue),
                    STOMPHeader(name: "receipt", value: receiptID),
                ] + userDefinedHeaders
            )
            self.sendFrame(subscribeFrame) { newFrame in
                newFrame.headers.first(where: { $0.name == "receipt-id" })?.value == receiptID
            }.assumeIsolated().whenComplete { result in
                switch result {
                case .success:
                    promise.succeed(subscriptionID)
                case .failure(let error):
                    self.subscriptions.removeSubscription(id: subscriptionID)
                    promise.fail(error)
                }
            }
        case .doNothing(let subscriptionID):
            promise.succeed(subscriptionID)
        }
    }

    func unsubscribe(
        id: Int,
        userDefinedHeaders: [STOMPHeader],
        promise: STOMPPromise<Void>
    ) {
        self.eventLoop.assertInEventLoop()
        switch self.subscriptions.unsubscribe(id: id) {
        case .unsubscribe(_):
            let receiptID = UUID().uuidString
            let unsubscribeFrame = STOMPFrame(
                command: .unsubscribe,
                headers: [
                    STOMPHeader(name: "id", value: String(id)),
                    STOMPHeader(name: "receipt", value: receiptID),
                ] + userDefinedHeaders
            )
            self.sendFrame(unsubscribeFrame) { newFrame in
                newFrame.headers.first(where: { $0.name == "receipt-id" })?.value == receiptID
            }.assumeIsolated().whenComplete { result in
                switch result {
                case .success:
                    promise.succeed(())
                case .failure(let error):
                    promise.fail(error)
                }
            }
        case .doNothing:
            promise.succeed(())
        }
    }
}

extension STOMPChannelHandler.Configuration {
    init(_ other: STOMPConnectionConfiguration) {
        self.init(
            authentication: other.authentication,
            virtualHost: other.virtualHost,
            connectTimeout: .init(other.connectTimeout),
            receiptTimeout: .init(other.receiptTimeout)
        )
    }
}
