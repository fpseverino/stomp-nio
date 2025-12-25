import Synchronization

@usableFromInline
struct IDGenerator: ~Copyable, Sendable {
    private let atomic: Atomic<Int>

    public init() {
        self.atomic = .init(0)
    }

    @usableFromInline
    func next() -> Int {
        self.atomic.wrappingAdd(1, ordering: .relaxed).newValue
    }
}
