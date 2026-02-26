import Testing

@testable import STOMPNIO

@Suite("STOMPContinuation Tests")
struct STOMPContinuationTests {
    @Test("Resume Continuation with Value")
    func resumeContinuationWithValue() async {
        let result = await withSTOMPContinuation { continuation in
            continuation.resume(returning: "hello")
        }
        #expect(result == "hello")
    }

    @Test("Resume Continuation with Void")
    func resumeContinuationWithVoid() async {
        await withSTOMPContinuation { continuation in
            continuation.resume(returning: ())
        }
    }

    @Test("Resume Throwing Continuation with Value")
    func resumeThrowingContinuationWithValue() async throws {
        let result = try await withSTOMPThrowingContinuation { continuation in
            continuation.resume(returning: "world")
        }
        #expect(result == "world")
    }

    @Test("Resume Throwing Continuation with Void")
    func resumeThrowingContinuationWithVoid() async throws {
        try await withSTOMPThrowingContinuation { continuation in
            continuation.resume(returning: ())
        }
    }

    @Test("Resume Throwing Continuation with Error")
    func resumeThrowingContinuationWithError() async {
        await #expect(throws: TestError.self) {
            let _: Int = try await withSTOMPThrowingContinuation { continuation in
                continuation.resume(throwing: TestError())
            }
        }
    }

    @Test("Succeed STOMPPromise")
    func succeedSTOMPPromise() async throws {
        let frame = STOMPFrame(command: .message, headers: [.destination: "/test"])
        let result: STOMPFrame = try await withSTOMPThrowingContinuation { continuation in
            let promise: STOMPPromise<STOMPFrame> = .swift(continuation)
            promise.succeed(frame)
        }
        #expect(result.command == .message)
        #expect(result.headers[.destination] == "/test")
    }

    @Test("Fail STOMPPromise")
    func failSTOMPPromise() async {
        await #expect(throws: TestError.self) {
            let _: STOMPFrame = try await withSTOMPThrowingContinuation { continuation in
                let promise: STOMPPromise<STOMPFrame> = .swift(continuation)
                promise.fail(TestError())
            }
        }
    }

    private struct TestError: Error {}
}
