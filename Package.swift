// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "stomp-nio",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "STOMPNIO", targets: ["STOMPNIO"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.7.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.91.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.26.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "STOMPNIO",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Configuration", package: "swift-configuration"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "STOMPNIOTests",
            dependencies: [
                .target(name: "STOMPNIO")
            ],
            swiftSettings: swiftSettings
        ),
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
