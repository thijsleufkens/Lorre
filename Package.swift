// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Lorre",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Lorre", targets: ["Lorre"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "LorreCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "LorreCapture",
            dependencies: ["LorreCore"]
        ),
        .executableTarget(
            name: "Lorre",
            dependencies: [
                "LorreCore",
                "LorreCapture",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(
            name: "LorreTests",
            dependencies: ["Lorre"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "LorreCaptureTests",
            dependencies: ["LorreCapture"]
        ),
        .testTarget(
            name: "LorreCoreTests",
            dependencies: ["LorreCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
