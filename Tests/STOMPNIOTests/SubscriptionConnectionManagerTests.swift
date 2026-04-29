import Foundation
import Logging
import NIOEmbedded
import Synchronization
import Testing

@testable import STOMPNIO

@Suite("SubscriptionConnectionManager Tests")
struct SubscriptionConnectionManagerTests {
    struct StateMachine {
        @Test
        func testAcquireRelease() {
            var stateMachine = SubscriptionConnectionStateMachine<String, Int, Int>()
            let action1 = stateMachine.get(id: 0, request: 10)
            let action2 = stateMachine.acquired(leaseID: 0, value: "Connection", releaseRequest: 100)
            let action3 = stateMachine.release(id: 0)
            #expect(action1 == .startAcquire(0))
            #expect(action2 == .yield([10]))
            #expect(action3 == .release(100))
        }

        @Test
        func testAcquireReleaseTwice() {
            var stateMachine = SubscriptionConnectionStateMachine<String, Int, Int>()
            do {
                let action1 = stateMachine.get(id: 0, request: 10)
                let action2 = stateMachine.acquired(leaseID: 0, value: "Connection", releaseRequest: 100)
                let action3 = stateMachine.release(id: 0)
                #expect(action1 == .startAcquire(0))
                #expect(action2 == .yield([10]))
                #expect(action3 == .release(100))
            }
            do {
                let action1 = stateMachine.get(id: 1, request: 11)
                let action2 = stateMachine.acquired(leaseID: 1, value: "Connection", releaseRequest: 101)
                let action3 = stateMachine.release(id: 1)
                #expect(action1 == .startAcquire(1))
                #expect(action2 == .yield([11]))
                #expect(action3 == .release(101))
            }
        }

        @Test
        func testConcurrentAcquireRelease() {
            var stateMachine = SubscriptionConnectionStateMachine<String, Int, Int>()
            let action1 = stateMachine.get(id: 0, request: 10)
            let action2 = stateMachine.get(id: 1, request: 11)
            let action3 = stateMachine.acquired(leaseID: 0, value: "Connection", releaseRequest: 100)
            let action4 = stateMachine.release(id: 1)
            let action5 = stateMachine.release(id: 0)
            #expect(action1 == .startAcquire(0))
            #expect(action2 == .doNothing)
            #expect(action3 == .yield([10, 11]))
            #expect(action4 == .doNothing)
            #expect(action5 == .release(100))
        }

        @Test
        func testGetAfterAcquire() {
            do {
                var stateMachine = SubscriptionConnectionStateMachine<String, Int, Int>()
                let action1 = stateMachine.get(id: 0, request: 10)
                let action2 = stateMachine.acquired(leaseID: 0, value: "Connection", releaseRequest: 100)
                let action3 = stateMachine.get(id: 1, request: 11)
                let action4 = stateMachine.release(id: 1)
                let action5 = stateMachine.release(id: 0)
                #expect(action1 == .startAcquire(0))
                #expect(action2 == .yield([10]))
                #expect(action3 == .completeRequest("Connection"))
                #expect(action4 == .doNothing)
                #expect(action5 == .release(100))
            }
            do {
                var stateMachine = SubscriptionConnectionStateMachine<String, Int, Int>()
                let action1 = stateMachine.get(id: 0, request: 10)
                let action2 = stateMachine.acquired(leaseID: 0, value: "Connection", releaseRequest: 100)
                let action3 = stateMachine.get(id: 1, request: 11)
                let action4 = stateMachine.release(id: 0)
                let action5 = stateMachine.release(id: 1)
                #expect(action1 == .startAcquire(0))
                #expect(action2 == .yield([10]))
                #expect(action3 == .completeRequest("Connection"))
                #expect(action4 == .doNothing)
                #expect(action5 == .release(100))
            }
        }

        @Test
        func testCancelWhileAcquiring() {
            var stateMachine = SubscriptionConnectionStateMachine<String, Int, Int>()
            let action1 = stateMachine.get(id: 0, request: 10)
            let action2 = stateMachine.cancel(id: 0)
            let action3 = stateMachine.acquired(leaseID: 0, value: "Connection", releaseRequest: 100)
            #expect(action1 == .startAcquire(0))
            #expect(action2 == .cancel(10))
            #expect(action3 == .release)
        }

        @Test
        func testCancelAfterAcquiring() {
            var stateMachine = SubscriptionConnectionStateMachine<String, Int, Int>()
            let action1 = stateMachine.get(id: 0, request: 10)
            let action2 = stateMachine.acquired(leaseID: 0, value: "Connection", releaseRequest: 100)
            let action3 = stateMachine.cancel(id: 0)
            #expect(action1 == .startAcquire(0))
            #expect(action2 == .yield([10]))
            #expect(action3 == .release(100))
        }

        @Test
        func testCancelWhileMulitpleAcquiring() {
            var stateMachine = SubscriptionConnectionStateMachine<String, Int, Int>()
            let action1 = stateMachine.get(id: 0, request: 10)
            let action2 = stateMachine.get(id: 1, request: 11)
            let action3 = stateMachine.cancel(id: 0)
            let action4 = stateMachine.acquired(leaseID: 0, value: "Connection", releaseRequest: 100)
            let action5 = stateMachine.release(id: 1)
            #expect(action1 == .startAcquire(0))
            #expect(action2 == .doNothing)
            #expect(action3 == .cancel(10))
            #expect(action4 == .yield([11]))
            #expect(action5 == .release(100))
        }

        @Test
        func testAcquireAfterCancel() {
            var stateMachine = SubscriptionConnectionStateMachine<String, Int, Int>()
            let action1 = stateMachine.get(id: 0, request: 10)
            let action2 = stateMachine.cancel(id: 0)
            let action3 = stateMachine.acquired(leaseID: 0, value: "Connection", releaseRequest: 100)
            let action4 = stateMachine.get(id: 1, request: 11)
            let action5 = stateMachine.acquired(leaseID: 1, value: "Connection", releaseRequest: 101)
            let action6 = stateMachine.release(id: 1)
            #expect(action1 == .startAcquire(0))
            #expect(action2 == .cancel(10))
            #expect(action3 == .release)
            #expect(action4 == .startAcquire(1))
            #expect(action5 == .yield([11]))
            #expect(action6 == .release(101))
        }
    }
}

extension SubscriptionConnectionStateMachine.GetAction: Equatable where Value: Equatable, Request: Equatable {
    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.startAcquire(let lhs), .startAcquire(let rhs)):
            lhs == rhs
        case (.doNothing, .doNothing):
            true
        case (.completeRequest(let lhs), .completeRequest(let rhs)):
            lhs == rhs
        default:
            false
        }
    }
}

extension SubscriptionConnectionStateMachine.AcquiredAction: Equatable where Value: Equatable, Request: Equatable & Comparable {
    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.yield(let lhs), .yield(let rhs)):
            lhs.sorted() == rhs.sorted()
        case (.release, .release):
            true
        default:
            false
        }
    }
}

extension SubscriptionConnectionStateMachine.CancelAction: Equatable where Value: Equatable, Request: Equatable, ReleaseRequest: Equatable {
    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.doNothing, .doNothing):
            true
        case (.cancel(let lhs), .cancel(let rhs)):
            lhs == rhs
        case (.release(let lhs), .release(let rhs)):
            lhs == rhs
        default:
            false
        }
    }
}

extension SubscriptionConnectionStateMachine.ReleaseAction: Equatable where Value: Equatable, Request: Equatable, ReleaseRequest: Equatable {
    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.doNothing, .doNothing):
            true
        case (.release(let lhs), .release(let rhs)):
            lhs == rhs
        default:
            false
        }
    }
}
