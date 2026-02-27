import Benchmark
import Logging
import STOMPNIO

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.peakMemoryResident, .mallocCountTotal],
        thresholds: [
            .peakMemoryResident: .init(
                // Tolerate up to 4% of difference compared to the threshold.
                relative: [.p90: 4],
                // Tolerate up to one million bytes of difference compared to the threshold.
                absolute: [.p90: 1_100_000]
            ),
            .mallocCountTotal: .init(
                // Tolerate up to 1% of difference compared to the threshold.
                relative: [.p90: 1],
                // Tolerate up to 2 malloc calls of difference compared to the threshold.
                absolute: [.p90: 2]
            ),
        ]
    )

    Benchmark("STOMPConnection Connection") { benchmark in
        var logger = Logger(label: "STOMPConnectionBenchmarks")
        logger.logLevel = .trace

        for _ in benchmark.scaledIterations {
            try await STOMPConnection.withConnection(address: .hostname("localhost"), logger: logger) { _ in }
        }
    }

    Benchmark("STOMPConnection Send") { benchmark in
        var logger = Logger(label: "STOMPConnectionBenchmarks")
        logger.logLevel = .trace

        try await STOMPConnection.withConnection(address: .hostname("localhost"), logger: logger) { connection in
            for _ in benchmark.scaledIterations {
                try await connection.send("Hello, STOMPNIO!", to: "/queue/benchmark-send")
            }
        }
    }

    Benchmark("STOMPConnection Subscribe") { benchmark in
        var logger = Logger(label: "STOMPConnectionBenchmarks")
        logger.logLevel = .trace

        try await STOMPConnection.withConnection(address: .hostname("localhost"), logger: logger) { connection in
            for _ in benchmark.scaledIterations {
                try await connection.subscribe(to: "/queue/benchmark-subscribe") { _ in }
            }
        }
    }
}
