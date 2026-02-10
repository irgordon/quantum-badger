// swift-tools-version: 6.0

import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .strictConcurrency(.complete),
]

let package = Package(
    name: "QuantumBadger",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "BadgerCore", targets: ["BadgerCore"]),
        .library(name: "BadgerRuntime", targets: ["BadgerRuntime"]),
        .library(name: "BadgerRemote", targets: ["BadgerRemote"]),
        .executable(name: "BadgerApp", targets: ["BadgerApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.21.2"),
    ],
    targets: [
        // MARK: - BadgerCore
        .target(
            name: "BadgerCore",
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - BadgerRuntime
        .target(
            name: "BadgerRuntime",
            dependencies: [
                "BadgerCore",
                .product(name: "MLX", package: "mlx-swift"),
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - BadgerRemote
        .target(
            name: "BadgerRemote",
            dependencies: [
                "BadgerRuntime",
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - BadgerApp
        .executableTarget(
            name: "BadgerApp",
            dependencies: [
                "BadgerRuntime",
                "BadgerRemote",
            ],
            swiftSettings: sharedSwiftSettings
        ),
        
        // MARK: - FileWriterService (XPC)
        .executableTarget(
            name: "FileWriterService",
            dependencies: [
                "BadgerCore",
            ],
            swiftSettings: sharedSwiftSettings
        ),
    ]
)
