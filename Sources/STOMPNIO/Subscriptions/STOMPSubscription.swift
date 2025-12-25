import NIOCore

/// A sequence of messages from a STOMP subscription.
public struct STOMPSubscription: AsyncSequence, Sendable {
    /// The type that the sequence produces.
    public typealias Element = STOMPFrame

    typealias BaseAsyncSequence = AsyncThrowingStream<STOMPFrame, any Error>
    typealias Continuation = BaseAsyncSequence.Continuation

    let base: BaseAsyncSequence

    static func makeStream() -> (Self, Self.Continuation) {
        let (stream, continuation) = BaseAsyncSequence.makeStream()
        return (.init(base: stream), continuation)
    }

    /// Creates a sequence of subscription messages.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: self.base.makeAsyncIterator())
    }

    /// An iterator that provides subscription messages.
    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: BaseAsyncSequence.AsyncIterator

        @concurrent
        public mutating func next() async throws -> Element? {
            try await self.base.next()
        }

        public mutating func next(isolation actor: isolated (any Actor)?) async throws(any Error) -> STOMPFrame? {
            try await self.base.next(isolation: actor)
        }
    }
}
