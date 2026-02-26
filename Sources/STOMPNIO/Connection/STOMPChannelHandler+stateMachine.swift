import BasicContainers
public import NIOCore

extension STOMPChannelHandler {
    @usableFromInline
    struct StateMachine<Context>: ~Copyable {
        @usableFromInline
        enum State: ~Copyable {
            case uninitialized
            case initialized(InitializedState)
            case connected(ConnectedState)
            case closing(ConnectedState)
            case closed((any Error)?)

            @usableFromInline
            var description: String {
                borrowing get {
                    switch self {
                    case .uninitialized: "uninitialized"
                    case .initialized: "initialized"
                    case .connected: "connected"
                    case .closing: "closing"
                    case .closed: "closed"
                    }
                }
            }
        }
        @usableFromInline
        var state: State

        @usableFromInline
        struct InitializedState: ~Copyable {
            let context: Context
            var connectTask: STOMPTask
            /// Cached `EventLoopPromise` from the connect task for `waitOnConnected`
            let connectPromise: EventLoopPromise<STOMPFrame>
        }

        @usableFromInline
        struct STOMPTasks: ~Copyable {
            var tasks: UniqueArray<STOMPTask>

            init() {
                self.tasks = UniqueArray()
            }

            mutating func append(_ task: consuming STOMPTask) {
                self.tasks.append(task)
            }

            mutating func remove(at index: UniqueArray<STOMPTask>.Index) -> STOMPTask {
                if index == tasks.endIndex - 1 {
                    return self.tasks.removeLast()
                } else {
                    self.tasks.swapAt(index, self.tasks.endIndex - 1)
                    return self.tasks.removeLast()
                }
            }

            mutating func removeFirst(where condition: (borrowing STOMPTask) -> Bool) -> STOMPTask? {
                for index in self.tasks.indices {
                    if condition(self.tasks[index]) {
                        return self.remove(at: index)
                    }
                }
                return nil
            }

            var isEmpty: Bool {
                self.tasks.isEmpty
            }

            var earliestDeadline: NIODeadline? {
                var earliest: NIODeadline? = nil
                for index in tasks.indices {
                    let d = tasks[index].deadline
                    if earliest == nil || d < earliest! {
                        earliest = d
                    }
                }
                return earliest
            }

            var deadlineCallbackAction: DeadlineCallbackAction {
                if self.isEmpty {
                    return .cancel
                } else if let earliest = self.earliestDeadline {
                    return .reschedule(earliest)
                } else {
                    return .doNothing
                }
            }

            enum ProcessFrameAction: ~Copyable {
                case succeedTask(STOMPTask, DeadlineCallbackAction)
                case failTask(STOMPTask, any Error)
                case unhandledTask
            }
            mutating func processFrame(_ frame: STOMPFrame) -> ProcessFrameAction {
                for index in self.tasks.indices {
                    do {
                        // should this task respond to inbound frame
                        if try self.tasks[index].checkInbound(frame) {
                            let task = self.remove(at: index)
                            return .succeedTask(task, self.deadlineCallbackAction)
                        }
                    } catch {
                        let task = self.remove(at: index)
                        return .failTask(task, error)
                    }
                }
                return .unhandledTask
            }

            mutating func failAll(_ error: any Error) {
                while !self.tasks.isEmpty {
                    self.tasks.removeLast().fail(error)
                }
            }
        }

        @usableFromInline
        struct ConnectedState: ~Copyable {
            let context: Context
            var tasks: STOMPTasks

            mutating func cancel(requestID: Int) -> STOMPTask? {
                self.tasks.removeFirst {
                    $0.requestID == requestID
                }
            }
        }

        init() {
            self.state = .uninitialized
        }

        private init(_ state: consuming State) {
            self.state = state
        }

        /// handler has become active
        @usableFromInline
        mutating func setInitialized(context: Context, connectTask: consuming STOMPTask, connectPromise: EventLoopPromise<STOMPFrame>) {
            switch consume self.state {
            case .uninitialized:
                self = .initialized(.init(context: context, connectTask: connectTask, connectPromise: connectPromise))
            case .initialized:
                preconditionFailure("Cannot set initialized state when state is initialized")
            case .connected:
                preconditionFailure("Cannot set initialized state when state is connected")
            case .closing:
                preconditionFailure("Cannot set initialized state when state is closing")
            case .closed:
                preconditionFailure("Cannot set initialized state when state is closed")
            }
        }

        @usableFromInline
        enum SendFrameAction: ~Copyable {
            case sendFrame(Context)
            case throwError(any Error, STOMPTask?)
        }

        /// handler wants to send a frame
        @usableFromInline
        mutating func sendFrame(_ task: consuming STOMPTask?) -> SendFrameAction {
            switch consume self.state {
            case .uninitialized:
                preconditionFailure("Cannot send frame when uninitialized")
            case .initialized:
                preconditionFailure("Cannot send frame when in initialized state")
            case .connected(var state):
                if let task {
                    state.tasks.append(task)
                }
                let context = state.context
                self = .connected(state)
                return .sendFrame(context)
            case .closing(let state):
                self = .closing(state)
                return .throwError(STOMPClientError.connectionClosing, task)
            case .closed(let error):
                self = .closed(error)
                return .throwError(STOMPClientError.connectionClosed, task)
            }
        }

        @usableFromInline
        enum DeadlineCallbackAction {
            case cancel
            case reschedule(NIODeadline)
            case doNothing
        }

        @usableFromInline
        enum ReceivedFrameAction: ~Copyable {
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
                    let context = state.context
                    let connectTask = state.connectTask
                    self = .connected(.init(context: context, tasks: .init()))
                    return .succeedTask(connectTask, .cancel)
                case .error:
                    let error = STOMPClientError.errorFrame(
                        message: frame.headers[.message],
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
                    let action = state.tasks.processFrame(frame)
                    self = .connected(state)
                    switch consume action {
                    case .succeedTask(let task, let deadlineCallback):
                        return .succeedTask(task, deadlineCallback)
                    case .failTask(let task, let error):
                        return .failTask(task, error)
                    case .unhandledTask:
                        return .unhandledTask
                    }
                case .error:
                    let error = STOMPClientError.errorFrame(
                        message: frame.headers[.message],
                        body: String(buffer: frame.body)
                    )
                    self = .connected(state)
                    return .closeConnection(error)
                default:
                    let error = STOMPClientError.unsolicitedFrame(message: "Received unexpected frame: \(frame.command)")
                    self = .connected(state)
                    return .closeConnection(error)
                }
            case .closing(var state):
                guard !state.tasks.isEmpty else {
                    preconditionFailure("Cannot be in closing state with no active tasks")
                }
                switch frame.command {
                case .message:
                    self = .closing(state)
                    return .messageReceived
                case .receipt:
                    for index in state.tasks.tasks.indices {
                        do {
                            if try state.tasks.tasks[index].checkInbound(frame) {
                                let task = state.tasks.remove(at: index)
                                if state.tasks.isEmpty {
                                    self = .closed(nil)
                                    return .succeedTask(task, .cancel)
                                } else {
                                    let deadlineCallback = state.tasks.deadlineCallbackAction
                                    self = .closing(state)
                                    return .succeedTask(task, deadlineCallback)
                                }
                            }
                        } catch {
                            let task = state.tasks.remove(at: index)
                            if state.tasks.isEmpty {
                                self = .closed(nil)
                                return .failTask(task, error)
                            } else {
                                self = .closing(state)
                                return .failTask(task, error)
                            }
                        }
                    }
                    self = .closing(state)
                    return .unhandledTask
                case .error:
                    let error = STOMPClientError.errorFrame(
                        message: frame.headers[.message],
                        body: String(buffer: frame.body)
                    )
                    self = .closed(error)
                    return .closeConnection(error)
                default:
                    let error = STOMPClientError.unsolicitedFrame(message: "Received unexpected frame: \(frame.command)")
                    self = .closed(error)
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
                let promise = state.connectPromise
                self = .initialized(state)
                return .waitForPromise(promise)
            case .connected(let state):
                self = .connected(state)
                return .done
            case .closing(let state):
                self = .closing(state)
                return .reportedClosed(nil)
            case .closed(let error):
                self = .closed(error)
                return .reportedClosed(error)
            }
        }

        @usableFromInline
        enum HitDeadlineAction: ~Copyable {
            case failTasksAndClose(Context, STOMPTasks)
            case reschedule(NIODeadline)
            case clearCallback
        }

        @usableFromInline
        mutating func hitDeadline(now: NIODeadline) -> HitDeadlineAction {
            switch consume self.state {
            case .uninitialized:
                preconditionFailure("Cannot cancel when uninitialized")
            case .initialized(let state):
                let deadline = state.connectTask.deadline
                if deadline <= now {
                    let context = state.context
                    var tasks = STOMPTasks()
                    tasks.append(state.connectTask)
                    self = .closed(STOMPClientError.timeout)
                    return .failTasksAndClose(context, tasks)
                } else {
                    self = .initialized(state)
                    return .reschedule(deadline)
                }
            case .connected(let state):
                if let earliestDeadline = state.tasks.earliestDeadline {
                    if earliestDeadline <= now {
                        let context = state.context
                        let tasks = state.tasks
                        self = .closed(STOMPClientError.timeout)
                        return .failTasksAndClose(context, tasks)
                    } else {
                        self = .connected(state)
                        return .reschedule(earliestDeadline)
                    }
                } else {
                    self = .connected(state)
                    return .clearCallback
                }
            case .closing(let state):
                guard !state.tasks.isEmpty else {
                    preconditionFailure("Cannot be in closing state with no active tasks")
                }
                if let earliestDeadline = state.tasks.earliestDeadline {
                    if earliestDeadline <= now {
                        let context = state.context
                        let tasks = state.tasks
                        self = .closed(STOMPClientError.timeout)
                        return .failTasksAndClose(context, tasks)
                    } else {
                        self = .closing(state)
                        return .reschedule(earliestDeadline)
                    }
                } else {
                    self = .closed(nil)
                    return .clearCallback
                }
            case .closed(let error):
                self = .closed(error)
                return .clearCallback
            }
        }

        @usableFromInline
        enum CancelAction: ~Copyable {
            case failTask(STOMPTask)
            case doNothing
        }

        /// handler wants to cancel a task
        @usableFromInline
        mutating func cancel(requestID: Int) -> CancelAction {
            switch consume self.state {
            case .uninitialized:
                preconditionFailure("Cannot cancel when uninitialized")
            case .initialized:
                preconditionFailure("Cannot cancel while in initialized state")
            case .connected(var state):
                let cancelledTask = state.cancel(requestID: requestID)
                self = .connected(state)
                if let cancelledTask {
                    return .failTask(cancelledTask)
                } else {
                    return .doNothing
                }
            case .closing(var state):
                let cancelledTask = state.cancel(requestID: requestID)
                self = .closing(state)
                if let cancelledTask {
                    return .failTask(cancelledTask)
                } else {
                    return .doNothing
                }
            case .closed(let error):
                self = .closed(error)
                return .doNothing
            }
        }

        @usableFromInline
        enum TriggerGracefulShutdownAction {
            case closeConnection(Context)
            case doNothing
        }
        /// Want to gracefully shutdown the handler
        @usableFromInline
        mutating func triggerGracefulShutdown() -> TriggerGracefulShutdownAction {
            switch consume self.state {
            case .uninitialized:
                self = .closed(nil)
                return .doNothing
            case .initialized(let state):
                let context = state.context
                var tasks = STOMPTasks()
                tasks.append(state.connectTask)
                self = .closing(.init(context: context, tasks: tasks))
                return .doNothing
            case .connected(let state):
                if !state.tasks.isEmpty {
                    let tasks = state.tasks
                    self = .closing(.init(context: state.context, tasks: tasks))
                    return .doNothing
                } else {
                    self = .closed(nil)
                    return .closeConnection(state.context)
                }
            case .closing(let state):
                self = .closing(state)
                return .doNothing
            case .closed(let error):
                self = .closed(error)
                return .doNothing
            }
        }

        @usableFromInline
        enum CloseAction: ~Copyable {
            case doNothing
            case failTasksAndClose(STOMPTasks)
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
                var tasks = STOMPTasks()
                tasks.append(state.connectTask)
                return .failTasksAndClose(tasks)
            case .connected(let state):
                self = .closed(nil)
                return .failTasksAndClose(state.tasks)
            case .closing(let state):
                self = .closed(nil)
                return .failTasksAndClose(state.tasks)
            case .closed(let error):
                self = .closed(error)
                return .doNothing
            }
        }

        @usableFromInline
        enum ScheduleHeartBeatAction {
            case schedule(Context)
            case doNothing
        }

        @usableFromInline
        mutating func scheduleHeartBeat() -> ScheduleHeartBeatAction {
            switch consume self.state {
            case .uninitialized:
                preconditionFailure("Cannot schedule heart-beat when uninitialized")
            case .initialized:
                preconditionFailure("Cannot schedule heart-beat when in initialized state")
            case .connected(let state):
                let context = state.context
                self = .connected(state)
                return .schedule(context)
            case .closing(let state):
                let context = state.context
                self = .closing(state)
                return .schedule(context)
            case .closed(let error):
                self = .closed(error)
                return .doNothing
            }
        }

        private static var uninitialized: Self {
            StateMachine(.uninitialized)
        }

        private static func initialized(_ state: consuming InitializedState) -> Self {
            StateMachine(.initialized(state))
        }

        private static func connected(_ state: consuming ConnectedState) -> Self {
            StateMachine(.connected(state))
        }

        private static func closing(_ state: consuming ConnectedState) -> Self {
            StateMachine(.closing(state))
        }

        private static func closed(_ error: (any Error)?) -> Self {
            StateMachine(.closed(error))
        }
    }
}
