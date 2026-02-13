// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BadgerCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BadgerCore",
            targets: ["BadgerCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "BadgerCore",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "BadgerCoreTests",
            dependencies: ["BadgerCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
    ]
)
