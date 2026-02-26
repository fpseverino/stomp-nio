public import NIOCore

@usableFromInline
enum STOMPPromise<T: Sendable>: ~Copyable, Sendable {
    case nio(EventLoopPromise<T>)
    case swift(STOMPContinuation<T, any Error>)
    case forget

    @usableFromInline
    consuming func succeed(_ t: T) {
        switch consume self {
        case .nio(let eventLoopPromise):
            eventLoopPromise.succeed(t)
        case .swift(let stompContinuation):
            stompContinuation.resume(returning: t)
        case .forget:
            break
        }
    }

    @usableFromInline
    consuming func fail(_ error: any Error) {
        switch consume self {
        case .nio(let eventLoopPromise):
            eventLoopPromise.fail(error)
        case .swift(let stompContinuation):
            stompContinuation.resume(throwing: error)
        case .forget:
            break
        }
    }
}

@usableFromInline
struct STOMPTask: ~Copyable, Sendable {
    let promise: STOMPPromise<STOMPFrame>
    let checkInbound: @Sendable (STOMPFrame) throws -> Bool
    let requestID: Int
    let deadline: NIODeadline

    @usableFromInline
    init(
        promise: consuming STOMPPromise<STOMPFrame>,
        requestID: Int,
        deadline: NIODeadline,
        checkInbound: @escaping @Sendable (STOMPFrame) throws -> Bool
    ) {
        self.promise = promise
        self.checkInbound = checkInbound
        self.requestID = requestID
        self.deadline = deadline
    }

    @usableFromInline
    consuming func succeed(_ frame: STOMPFrame) {
        promise.succeed(frame)
    }

    @usableFromInline
    consuming func fail(_ error: any Error) {
        promise.fail(error)
    }
}
