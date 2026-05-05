// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftUtils",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SwiftUtils", targets: ["SwiftUtils"]),
    ],
    targets: [
        .target(name: "SwiftUtils", path: "Sources"),
        .testTarget(name: "SwiftUtilsTests", dependencies: ["SwiftUtils"], path: "Tests"),
    ]
)
