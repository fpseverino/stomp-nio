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
        @usableFromInline
        let authentication: STOMPConnectionConfiguration.Authentication?
        @usableFromInline
        let virtualHost: String?
        @usableFromInline
        let heartBeat: (outgoing: TimeAmount, incoming: TimeAmount)
        @usableFromInline
        let connectTimeout: TimeAmount
        @usableFromInline
        let receiptTimeout: TimeAmount
        @usableFromInline
        let connectHeaders: STOMPHeaders
    }

    struct STOMPDeadlineSchedule: NIOScheduledCallbackHandler {
        let channelHandler: NIOLoopBound<STOMPChannelHandler>

        func handleScheduledCallback(eventLoop: some NIOCore.EventLoop) {
            let channelHandler = self.channelHandler.value
            switch channelHandler.stateMachine.hitDeadline(now: .now()) {
            case .failTasksAndClose(let context, var tasks):
                let error = STOMPClientError.timeout
                tasks.failAll(error)
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

    private let decoder: NIOSingleStepByteToMessageProcessor<STOMPFrameDecoder>
    private let logger: Logger
    @usableFromInline
    let configuration: Configuration

    private var heartBeatFrequency: TimeAmount
    private var lastHeartBeatTime: NIODeadline
    private var heartBeatCallback: NIOScheduledCallback?

    init(configuration: Configuration, eventLoop: any EventLoop, logger: Logger) {
        self.configuration = configuration
        self.eventLoop = eventLoop
        self.subscriptions = STOMPSubscriptions(logger: logger)
        self.decoder = NIOSingleStepByteToMessageProcessor(STOMPFrameDecoder())
        self.stateMachine = .init()
        self.logger = logger

        self.heartBeatFrequency = .milliseconds(0)
        self.lastHeartBeatTime = .now()
        self.heartBeatCallback = nil
    }

    @usableFromInline
    func setInitialized(context: ChannelHandlerContext) {
        let outgoingHeartBeat = self.configuration.heartBeat.outgoing.nanoseconds / 1_000_000
        let incomingHeartBeat = self.configuration.heartBeat.incoming.nanoseconds / 1_000_000
        var headers: STOMPHeaders =
            self.configuration.connectHeaders + [
                .acceptVersion: "1.0,1.1,1.2",
                .heartBeat: "\(outgoingHeartBeat),\(incomingHeartBeat)",
            ]
        if let authentication = self.configuration.authentication {
            headers.append(.init(name: .login, value: authentication.login))
            headers.append(.init(name: .passcode, value: authentication.passcode))
        }
        if let virtualHost = self.configuration.virtualHost {
            headers.append(.init(name: .host, value: virtualHost))
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
            connectTask: .init(promise: .nio(promise), requestID: 0, deadline: deadline) { $0.command == .connected },
            connectPromise: promise
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
        self.heartBeatCallback?.cancel()
        self.heartBeatCallback = nil
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
        self.lastHeartBeatTime = .now()
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

    @usableFromInline
    func cancel(requestID: Int) {
        self.eventLoop.assertInEventLoop()
        switch self.stateMachine.cancel(requestID: requestID) {
        case .failTask(let cancelledTask):
            cancelledTask.fail(STOMPClientError.cancelledTask)
        case .doNothing:
            break
        }
    }

    func handleFrame(context: ChannelHandlerContext, frame: STOMPFrame) {
        self.logger.trace("Received STOMP message: \(frame.command.rawValue)")

        switch self.stateMachine.receivedFrame(frame) {
        case .succeedTask(let task, let deadlineAction):
            // Handle heart-beat negotiation on CONNECTED frame
            if frame.command == .connected,
                self.configuration.heartBeat.outgoing > .milliseconds(0),
                let heartBeatHeader = frame.headers[.heartBeat]
            {
                let components = heartBeatHeader.split(separator: ",").compactMap { Int64($0) }
                if components.count == 2 {
                    let serverIncomingFrequency = components[1]
                    if serverIncomingFrequency > 0 {
                        self.heartBeatFrequency = max(self.configuration.heartBeat.outgoing, .milliseconds(serverIncomingFrequency))
                        self.lastHeartBeatTime = .now()
                        if self.heartBeatCallback == nil {
                            self.scheduleHeartBeatCallback()
                        }
                    }
                }
            }
            self.processDeadlineCallbackAction(action: deadlineAction)
            task.succeed(frame)
        case .failTask(let task, let error):
            task.fail(error)
        case .unhandledTask:
            break
        case .messageReceived:
            do {
                guard let subscriptionHeader = frame.headers[.subscription],
                    let messageIDHeader = frame.headers[.messageID]
                else {
                    throw STOMPClientError.missingHeader(message: "Missing subscription or message-id header in MESSAGE frame")
                }
                if let subscriptionID = UInt(subscriptionHeader), self.subscriptions.shouldAcknowledge(id: subscriptionID) {
                    var headers: STOMPHeaders = [
                        .subscription: subscriptionHeader,
                        .messageID: messageIDHeader,
                    ]
                    if let ackHeader = frame.headers[values: .ack].first.map({ STOMPHeader(name: .id, value: $0) }) {
                        headers.append(ackHeader)
                    }
                    if let transactionID = self.subscriptions.transactionID(for: subscriptionID) {
                        headers.append(STOMPHeader(name: .transaction, value: transactionID))
                    }
                    let ackFrame = STOMPFrame(
                        command: .ack,
                        headers: headers
                    )
                    _ = context.channel.writeAndFlush(ackFrame)
                }
                try self.subscriptions.notify(frame)
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
        case .failTasksAndClose(var tasks):
            tasks.failAll(error)
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
    func sendFrameNoWait(_ frame: STOMPFrame) throws {
        self.eventLoop.assertInEventLoop()
        switch self.stateMachine.sendFrame(nil) {
        case .sendFrame(let context):
            _ = context.channel.writeAndFlush(frame)
        case .throwError(let error, _):
            throw error
        }
    }

    @usableFromInline
    func sendFrame(
        _ frame: STOMPFrame,
        promise: consuming STOMPPromise<STOMPFrame>,
        requestID: Int,
        checkInbound: @escaping @Sendable (STOMPFrame) throws -> Bool
    ) {
        self.eventLoop.assertInEventLoop()
        let deadline = .now() + self.configuration.receiptTimeout
        let task = STOMPTask(promise: promise, requestID: requestID, deadline: deadline, checkInbound: checkInbound)
        switch self.stateMachine.sendFrame(task) {
        case .sendFrame(let context):
            _ = context.channel.writeAndFlush(frame)
            if self.deadlineCallback == nil {
                self.scheduleDeadlineCallback(deadline: deadline)
            }
        case .throwError(let error, let task):
            task?.fail(error)
        }
    }

    private func sendFrame(
        _ frame: STOMPFrame,
        requestID: Int,
        checkInbound: @escaping @Sendable (STOMPFrame) throws -> Bool
    ) -> EventLoopFuture<STOMPFrame> {
        let promise = self.eventLoop.makePromise(of: STOMPFrame.self)
        self.sendFrame(frame, promise: .nio(promise), requestID: requestID, checkInbound: checkInbound)
        return promise.futureResult
    }

    func subscribe(
        streamContinuation: STOMPSubscription.Continuation,
        destination: String,
        ackMode: STOMPSubscription.AckMode,
        userDefinedHeaders: STOMPHeaders,
        transactionID: String?,
        continuation: CheckedContinuation<UInt, any Error>,
        requestID: Int
    ) {
        self.eventLoop.assertInEventLoop()
        let subscription = self.subscriptions.addSubscription(
            continuation: streamContinuation,
            destination: destination,
            ackMode: ackMode,
            transactionID: transactionID
        )
        let subscriptionID = subscription.id
        let receiptID = UUID().uuidString
        let subscribeFrame = STOMPFrame(
            command: .subscribe,
            headers: userDefinedHeaders + [
                .destination: destination,
                .id: String(subscriptionID),
                .ack: ackMode.rawValue,
                .receipt: receiptID,
            ]
        )
        self.sendFrame(subscribeFrame, requestID: requestID) { newFrame in
            newFrame.headers[.receiptID] == receiptID
        }.assumeIsolated().whenComplete { result in
            switch result {
            case .success:
                continuation.resume(returning: subscriptionID)
            case .failure(let error):
                self.subscriptions.removeSubscription(id: subscriptionID)
                continuation.resume(throwing: error)
            }
        }
    }

    func unsubscribe(
        id: UInt,
        userDefinedHeaders: STOMPHeaders,
        continuation: CheckedContinuation<Void, any Error>,
        requestID: Int
    ) {
        self.eventLoop.assertInEventLoop()
        self.subscriptions.removeSubscription(id: id)
        let receiptID = UUID().uuidString
        let unsubscribeFrame = STOMPFrame(
            command: .unsubscribe,
            headers: userDefinedHeaders + [
                .id: String(id),
                .receipt: receiptID,
            ]
        )
        self.sendFrame(unsubscribeFrame, requestID: requestID) { newFrame in
            newFrame.headers[.receiptID] == receiptID
        }.assumeIsolated().whenComplete { result in
            switch result {
            case .success:
                continuation.resume(returning: ())
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    struct HeartBeatSchedule: NIOScheduledCallbackHandler {
        let channelHandler: NIOLoopBound<STOMPChannelHandler>

        func handleScheduledCallback(eventLoop: some EventLoop) {
            let channelHandler = self.channelHandler.value
            switch channelHandler.stateMachine.scheduleHeartBeat() {
            case .doNothing:
                break
            case .schedule(let context):
                // If `lastHeartBeatTime` plus the frequency is less than now send EOL,
                // otherwise reschedule task
                if channelHandler.lastHeartBeatTime + channelHandler.heartBeatFrequency <= .now() {
                    guard context.channel.isActive else { return }
                    var buffer = context.channel.allocator.buffer(capacity: 1)
                    buffer.writeString("\n")
                    context.writeAndFlush(channelHandler.wrapOutboundOut(buffer))
                        .assumeIsolated()
                        .whenComplete { result in
                            switch result {
                            case .failure(let error):
                                channelHandler.failTasksAndCloseSubscriptions(with: error)
                                context.fireErrorCaught(error)
                            case .success:
                                break
                            }
                            channelHandler.lastHeartBeatTime = .now()
                            channelHandler.scheduleHeartBeatCallback()
                        }
                } else {
                    channelHandler.scheduleHeartBeatCallback()
                }
            }
        }
    }

    func scheduleHeartBeatCallback() {
        self.heartBeatCallback = try? self.eventLoop.scheduleCallback(
            at: self.lastHeartBeatTime + self.heartBeatFrequency,
            handler: HeartBeatSchedule(channelHandler: .init(self, eventLoop: self.eventLoop))
        )
    }

    func heartBeat() throws {
        self.eventLoop.assertInEventLoop()
        switch self.stateMachine.sendFrame(nil) {
        case .sendFrame(let context):
            var buffer = context.channel.allocator.buffer(capacity: 1)
            buffer.writeString("\n")
            _ = context.writeAndFlush(self.wrapOutboundOut(buffer))
        case .throwError(let error, _):
            throw error
        }
    }
}

extension STOMPChannelHandler.Configuration {
    init(_ other: STOMPConnectionConfiguration) {
        self.init(
            authentication: other.authentication,
            virtualHost: other.virtualHost,
            heartBeat: (
                outgoing: .init(other.heartBeat.outgoing),
                incoming: .init(other.heartBeat.incoming)
            ),
            connectTimeout: .init(other.connectTimeout),
            receiptTimeout: .init(other.receiptTimeout),
            connectHeaders: other.connectHeaders
        )
    }
}
