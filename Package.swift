// swift-tools-version: 6.0

import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6), // Explicit Swift 6 mode
    .enableUpcomingFeature("ExistentialAny"), // Forward compatibility
]

let package = Package(
    name: "QuantumBadger",
    platforms: [
        .macOS(.v15), // Targeting macOS Sequoia (15.0)+
    ],
    products: [
        // MARK: - Dynamic Libraries (Critical for MLX & Tests)
        .library(
            name: "BadgerCore", 
            type: .dynamic, 
            targets: ["BadgerCore"]
        ),
        .library(
            name: "BadgerRuntime", 
            type: .dynamic, 
            targets: ["BadgerRuntime"]
        ),
        .library(
            name: "BadgerRemote", 
            type: .dynamic, 
            targets: ["BadgerRemote"]
        ),
        
        // MARK: - Executables
        .executable(name: "BadgerApp", targets: ["BadgerApp"]),
        // We export the XPC service so it can be built, 
        // even if SwiftPM doesn't bundle it automatically.
        .executable(name: "FileWriterService", targets: ["FileWriterService"]),
    ],
    dependencies: [
        // Updated to a newer version likely to support Swift 6 Strict Concurrency
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.22.0"), 
    ],
    targets: [
        // MARK: - Core (Shared Logic)
        .target(
            name: "BadgerCore",
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Runtime (The Brain + MLX)
        .target(
            name: "BadgerRuntime",
            dependencies: [
                "BadgerCore",
                .product(name: "MLX", package: "mlx-swift"),
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Remote (Networking)
        .target(
            name: "BadgerRemote",
            dependencies: [
                "BadgerRuntime",
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - The App
        .executableTarget(
            name: "BadgerApp",
            dependencies: [
                "BadgerCore",     // Explicit dependency often helps resolution
                "BadgerRuntime",
                "BadgerRemote",
            ],
            // Resources might be needed if this is a GUI app (Assets.xcassets)
            // resources: [.process("Resources")], 
            swiftSettings: sharedSwiftSettings
        ),
        
        // MARK: - XPC Service
        // Note: This needs to be embedded into the App bundle manually or via Xcode.
        .executableTarget(
            name: "FileWriterService",
            dependencies: [
                "BadgerCore", // XPC should typically NOT link Runtime/MLX to keep it lightweight
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Tests
        .testTarget(
            name: "QuantumBadgerTests",
            dependencies: [
                "BadgerCore",
                "BadgerRuntime",
                "BadgerRemote",
            ],
            swiftSettings: sharedSwiftSettings
        ),
    ]
)
