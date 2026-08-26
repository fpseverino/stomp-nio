import Logging
import Testing

struct DefaultLoggerTrait: TestTrait, SuiteTrait, TestScoping {
    let logLevel: Logger.Level

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        var logger = Logger(label: test.displayName ?? test.name)
        logger.logLevel = logLevel
        try await withLogger(logger) { _ in
            try await function()
        }
    }
}

extension Trait where Self == DefaultLoggerTrait {
    /// A trait that provides a default task-local `Logger` for all tests and suites.
    ///
    /// The logger is configured with the provided log level and a label that corresponds to the test display name.
    static func defaultLogger(logLevel: Logger.Level) -> Self { Self(logLevel: logLevel) }
}
