// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftUtils",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        // Individual libraries — pick only what you need
        .library(name: "SwiftUtilsExtensions", targets: ["SwiftUtilsExtensions"]),
        .library(name: "SwiftUtilsNetworking", targets: ["SwiftUtilsNetworking"]),
        .library(name: "SwiftUtilsStorage", targets: ["SwiftUtilsStorage"]),
        .library(name: "SwiftUtilsConcurrency", targets: ["SwiftUtilsConcurrency"]),
        .library(name: "SwiftUtilsHelpers", targets: ["SwiftUtilsHelpers"]),

        // Umbrella library — includes everything
        .library(name: "SwiftUtils", targets: [
            "SwiftUtilsExtensions",
            "SwiftUtilsNetworking",
            "SwiftUtilsStorage",
            "SwiftUtilsConcurrency",
            "SwiftUtilsHelpers",
        ]),
    ],
    targets: [
        // Source targets
        .target(name: "SwiftUtilsExtensions", path: "Sources/Extensions"),
        .target(name: "SwiftUtilsNetworking", path: "Sources/Networking"),
        .target(name: "SwiftUtilsStorage", path: "Sources/Storage"),
        .target(name: "SwiftUtilsConcurrency", path: "Sources/Concurrency"),
        .target(name: "SwiftUtilsHelpers", path: "Sources/Helpers"),

        // Test targets
        .testTarget(name: "SwiftUtilsExtensionsTests", dependencies: ["SwiftUtilsExtensions"], path: "Tests/ExtensionsTests"),
        .testTarget(name: "SwiftUtilsNetworkingTests", dependencies: ["SwiftUtilsNetworking"], path: "Tests/NetworkingTests"),
        .testTarget(name: "SwiftUtilsStorageTests", dependencies: ["SwiftUtilsStorage"], path: "Tests/StorageTests"),
        .testTarget(name: "SwiftUtilsConcurrencyTests", dependencies: ["SwiftUtilsConcurrency"], path: "Tests/ConcurrencyTests"),
        .testTarget(name: "SwiftUtilsHelpersTests", dependencies: ["SwiftUtilsHelpers"], path: "Tests/HelpersTests"),
    ]
)
