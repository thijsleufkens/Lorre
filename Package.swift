// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Lorre",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Lorre", targets: ["Lorre"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "Lorre",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "LorreTests",
            dependencies: ["Lorre"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
