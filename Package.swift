// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuantumBadger",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuantumBadger", targets: ["QuantumBadgerApp"]),
        .library(name: "QuantumBadgerRuntime", targets: ["QuantumBadgerRuntime"]),
        .executable(name: "QuantumBadgerUntrustedParser", targets: ["QuantumBadgerUntrustedParser"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "QuantumBadgerRuntime",
            dependencies: [],
            path: "Sources/QuantumBadgerRuntime"
        ),
        .executableTarget(
            name: "QuantumBadgerUntrustedParser",
            dependencies: ["QuantumBadgerRuntime"],
            path: "Sources/QuantumBadgerUntrustedParser",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "QuantumBadgerApp",
            dependencies: ["QuantumBadgerRuntime"],
            path: "Sources/QuantumBadgerApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "QuantumBadgerTests",
            dependencies: ["QuantumBadgerApp", "QuantumBadgerRuntime"],
            path: "Tests/QuantumBadgerTests"
        )
    ]
)
