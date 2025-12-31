#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension STOMPConnection {
    /// Starts a STOMP transaction and closes it when the `process` closure returns or throws.
    ///
    /// The closure receives a ``STOMPTransaction`` instance to perform operations within the transaction.
    ///
    /// - Parameter process: Closure where operations within the transaction are performed.
    ///
    /// - Returns: The value returned by the `process` closure.
    public nonisolated func withTransaction<Value>(
        _ process: (STOMPTransaction) async throws -> Value
    ) async throws -> Value {
        let transactionID = UUID().uuidString
        _ = try await self.send(
            frame: .init(
                command: .begin,
                headers: [.transaction: transactionID]
            )
        )

        var closureHasFinished: Bool = false
        do {
            let value = try await process(STOMPTransaction(id: transactionID, connection: self))
            closureHasFinished = true
            _ = try await self.send(
                frame: .init(
                    command: .commit,
                    headers: [.transaction: transactionID]
                )
            )
            return value
        } catch {
            if !closureHasFinished {
                _ = try await self.send(
                    frame: .init(
                        command: .abort,
                        headers: [.transaction: transactionID]
                    )
                )
            }
            throw error
        }
    }
}
