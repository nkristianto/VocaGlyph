// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VocaGlyph",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "VocaGlyphLib",
            targets: ["VocaGlyphLib"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.10.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.30.6"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "VocaGlyphLib",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/VocaGlyph", // source folder kept as-is, only module name changes
            exclude: ["App/main.swift"], // Entry point handled by Xcode app target via @NSApplicationDelegateAdaptor
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "VocaGlyphTests",
            dependencies: ["VocaGlyphLib"]
        ),
    ]
)
