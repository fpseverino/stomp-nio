import NIOCore

/// A sequence of messages from a STOMP subscription.
public struct STOMPSubscription: AsyncSequence, Sendable {
    /// The type that the sequence produces.
    public typealias Element = STOMPFrame
    public typealias AsyncIterator = AsyncThrowingStream<STOMPFrame, any Error>.AsyncIterator

    typealias Continuation = AsyncThrowingStream<STOMPFrame, any Error>.Continuation

    let base: AsyncThrowingStream<STOMPFrame, any Error>

    static func makeStream() -> (Self, Self.Continuation) {
        let (stream, continuation) = AsyncThrowingStream<STOMPFrame, any Error>.makeStream()
        return (.init(base: stream), continuation)
    }

    /// Creates a sequence of subscription messages.
    public func makeAsyncIterator() -> AsyncIterator {
        self.base.makeAsyncIterator()
    }
}
