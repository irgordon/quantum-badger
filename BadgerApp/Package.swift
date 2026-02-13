// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BadgerApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BadgerApp",
            targets: ["BadgerApp"]
        ),
    ],
    dependencies: [
        // Local dependencies
        .package(path: "../BadgerCore"),
        .package(path: "../BadgerRuntime"),
    ],
    targets: [
        .target(
            name: "BadgerApp",
            dependencies: [
                .product(name: "BadgerCore", package: "BadgerCore"),
                .product(name: "BadgerRuntime", package: "BadgerRuntime"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "BadgerAppTests",
            dependencies: ["BadgerApp"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
    ]
)
