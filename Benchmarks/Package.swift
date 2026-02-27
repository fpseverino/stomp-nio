// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "benchmarks",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../"),
        .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.29.11"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "STOMPNIOBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "STOMPNIO", package: "stomp-nio"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "STOMPNIOBenchmarks",
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("ImmutableWeakCaptures"),
    ]
}
