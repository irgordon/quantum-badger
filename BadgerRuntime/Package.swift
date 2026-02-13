// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BadgerRuntime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BadgerRuntime",
            targets: ["BadgerRuntime"]
        ),
    ],
    dependencies: [
        // Local dependency on BadgerCore
        .package(path: "../BadgerCore"),
        // MLX Swift for local inference
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
    ],
    targets: [
        .target(
            name: "BadgerRuntime",
            dependencies: [
                .product(name: "BadgerCore", package: "BadgerCore"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "BadgerRuntimeTests",
            dependencies: ["BadgerRuntime"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
    ]
)
