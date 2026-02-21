// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "voice-to-text",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "voice-to-text",
            targets: ["voice-to-text"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.10.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "voice-to-text",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "voice-to-textTests",
            dependencies: ["voice-to-text"]
        ),
    ]
)
