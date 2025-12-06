public import NIOCore

extension STOMPChannelHandler {
    @usableFromInline
    struct StateMachine<Context>: ~Copyable {
        @usableFromInline
        enum State: ~Copyable {
            case uninitialized
            case initialized(InitializedState)
            case connected(ConnectedState)
            case closed((any Error)?)

            @usableFromInline
            var description: String {
                borrowing get {
                    switch self {
                    case .uninitialized: "uninitialized"
                    case .initialized: "initialized"
                    case .connected: "connected"
                    case .closed: "closed"
                    }
                }
            }
        }
        @usableFromInline
        var state: State

        @usableFromInline
        struct InitializedState {
            let context: Context
            let connectTask: STOMPTask
        }

        @usableFromInline
        struct ConnectedState {
            let context: Context
            var tasks: [STOMPTask]
        }

        init() {
            self.state = .uninitialized
        }

        private init(_ state: consuming State) {
            self.state = state
        }

        /// handler has become active
        @usableFromInline
        mutating func setInitialized(context: Context, connectTask: STOMPTask) {
            switch consume self.state {
            case .uninitialized:
                self = .initialized(.init(context: context, connectTask: connectTask))
            case .initialized:
                preconditionFailure("Cannot set initialized state when state is initialized")
            case .connected:
                preconditionFailure("Cannot set initialized state when state is connected")
            case .closed:
                preconditionFailure("Cannot set initialized state when state is closed")
            }
        }

        @usableFromInline
        enum SendFrameAction {
            case sendFrame(Context)
            case throwError(any Error)
        }

        /// handler wants to send a frame
        @usableFromInline
        mutating func sendFrame(_ task: STOMPTask) -> SendFrameAction {
            switch consume self.state {
            case .uninitialized:
                preconditionFailure("Cannot send frame when uninitialized")
            case .initialized:
                preconditionFailure("Cannot send frame when in initialized state")
            case .connected(var state):
                state.tasks.append(task)
                self = .connected(state)
                return .sendFrame(state.context)
            case .closed(let error):
                self = .closed(error)
                return .throwError(STOMPClientError.connectionClosed)
            }
        }

        @usableFromInline
        enum DeadlineCallbackAction {
            case cancel
            case reschedule(NIODeadline)
            case doNothing
        }

        @usableFromInline
        enum ReceivedFrameAction {
            case messageReceived
            case succeedTask(STOMPTask, DeadlineCallbackAction)
            case failTask(STOMPTask, any Error)
            case unhandledTask
            case closeConnection(any Error)
        }

        @usableFromInline
        mutating func receivedFrame(_ frame: STOMPFrame) -> ReceivedFrameAction {
            switch consume self.state {
            case .uninitialized:
                preconditionFailure("Cannot receive frame when uninitialized")
            case .initialized(let state):
                switch frame.command {
                case .connected:
                    self = .connected(.init(context: state.context, tasks: []))
                    return .succeedTask(state.connectTask, .cancel)
                case .error:
                    let error = STOMPClientError.errorFrame(
                        message: frame.headers.first(where: { $0.name == "message" })?.value,
                        body: String(buffer: frame.body)
                    )
                    self = .closed(error)
                    return .failTask(state.connectTask, error)
                default:
                    let error = STOMPClientError.unsolicitedFrame(message: "Received unexpected frame: \(frame.command)")
                    self = .closed(error)
                    return .failTask(state.connectTask, error)
                }
            case .connected(var state):
                switch frame.command {
                case .message:
                    self = .connected(state)
                    return .messageReceived
                case .receipt:
                    for task in state.tasks {
                        do {
                            if try task.checkInbound(frame) {
                                state.tasks.removeAll { $0 === task }
                                self = .connected(state)
                                let deadlineCallback: DeadlineCallbackAction =
                                    if state.tasks.isEmpty {
                                        .cancel
                                    } else {
                                        if let earliestDeadline = state.tasks.map({ $0.deadline }).min() {
                                            .reschedule(earliestDeadline)
                                        } else {
                                            .doNothing
                                        }
                                    }
                                return .succeedTask(task, deadlineCallback)
                            }
                        } catch {
                            state.tasks.removeAll { $0 === task }
                            self = .connected(state)
                            return .failTask(task, error)
                        }
                    }
                    self = .connected(state)
                    return .unhandledTask
                case .error:
                    let error = STOMPClientError.errorFrame(
                        message: frame.headers.first(where: { $0.name == "message" })?.value,
                        body: String(buffer: frame.body)
                    )
                    self = .connected(state)
                    return .closeConnection(error)
                default:
                    let error = STOMPClientError.unsolicitedFrame(message: "Received unexpected frame: \(frame.command)")
                    self = .connected(state)
                    return .closeConnection(error)
                }
            case .closed(let error):
                guard let error else {
                    preconditionFailure("Cannot receive frame on closed connection with no error")
                }
                self = .closed(error)
                return .closeConnection(error)
            }
        }

        @usableFromInline
        enum WaitOnConnectedAction {
            case waitForPromise(EventLoopPromise<STOMPFrame>)
            case reportedClosed((any Error)?)
            case done
        }

        mutating func waitOnConnected() -> WaitOnConnectedAction {
            switch consume self.state {
            case .uninitialized:
                preconditionFailure("Cannot wait until connection has succeeded")
            case .initialized(let state):
                switch state.connectTask.promise {
                case .nio(let promise):
                    self = .initialized(state)
                    return .waitForPromise(promise)
                case .swift, .forget:
                    preconditionFailure("Initialized state cannot be setup with a Swift continuation")
                }
            case .connected(let state):
                self = .connected(state)
                return .done
            case .closed(let error):
                self = .closed(error)
                return .reportedClosed(error)
            }
        }

        @usableFromInline
        enum HitDeadlineAction {
            case failTasksAndClose(Context, [STOMPTask])
            case reschedule(NIODeadline)
            case clearCallback
        }

        @usableFromInline
        mutating func hitDeadline(now: NIODeadline) -> HitDeadlineAction {
            switch consume self.state {
            case .uninitialized:
                preconditionFailure("Cannot cancel when uninitialized")
            case .initialized(let state):
                if state.connectTask.deadline <= now {
                    self = .closed(STOMPClientError.timeout)
                    return .failTasksAndClose(state.context, [state.connectTask])
                } else {
                    self = .initialized(state)
                    return .reschedule(state.connectTask.deadline)
                }
            case .connected(let state):
                if let earliestDeadline = state.tasks.map({ $0.deadline }).min() {
                    if earliestDeadline <= now {
                        self = .closed(STOMPClientError.timeout)
                        return .failTasksAndClose(state.context, state.tasks)
                    } else {
                        self = .connected(state)
                        return .reschedule(earliestDeadline)
                    }
                } else {
                    self = .connected(state)
                    return .clearCallback
                }
            case .closed(let error):
                self = .closed(error)
                return .clearCallback
            }
        }

        @usableFromInline
        enum CloseAction {
            case doNothing
            case failTasksAndClose([STOMPTask])
        }

        /// Want to close the connection
        @usableFromInline
        mutating func close() -> CloseAction {
            switch consume self.state {
            case .uninitialized:
                self = .closed(nil)
                return .doNothing
            case .initialized(let state):
                self = .closed(nil)
                return .failTasksAndClose([state.connectTask])
            case .connected(let state):
                self = .closed(nil)
                return .failTasksAndClose(state.tasks)
            case .closed(let error):
                self = .closed(error)
                return .doNothing
            }
        }

        private static var uninitialized: Self {
            StateMachine(.uninitialized)
        }

        private static func initialized(_ state: InitializedState) -> Self {
            StateMachine(.initialized(state))
        }

        private static func connected(_ state: ConnectedState) -> Self {
            StateMachine(.connected(state))
        }

        private static func closed(_ error: (any Error)?) -> Self {
            StateMachine(.closed(error))
        }
    }
}
