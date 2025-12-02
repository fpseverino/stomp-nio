public import NIOCore

@usableFromInline
enum STOMPPromise<T: Sendable>: Sendable {
    case nio(EventLoopPromise<T>)
    case swift(CheckedContinuation<T, any Error>)
    case forget

    func succeed(_ t: T) {
        switch self {
        case .nio(let eventLoopPromise):
            eventLoopPromise.succeed(t)
        case .swift(let checkedContinuation):
            checkedContinuation.resume(returning: t)
        case .forget:
            break
        }
    }

    func fail(_ error: any Error) {
        switch self {
        case .nio(let eventLoopPromise):
            eventLoopPromise.fail(error)
        case .swift(let checkedContinuation):
            checkedContinuation.resume(throwing: error)
        case .forget:
            break
        }
    }
}

@usableFromInline
final class STOMPTask: Sendable {
    let promise: STOMPPromise<STOMPFrame>
    let checkInbound: @Sendable (STOMPFrame) throws -> Bool
    let deadline: NIODeadline

    init(
        promise: STOMPPromise<STOMPFrame>,
        deadline: NIODeadline,
        checkInbound: @escaping @Sendable (STOMPFrame) throws -> Bool
    ) {
        self.promise = promise
        self.checkInbound = checkInbound
        self.deadline = deadline
    }
}
