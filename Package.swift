// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "peregrine",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/sushichop/Puppy", from: "0.7.0"),
        .package(
            url: "https://github.com/Zollerboy1/SwiftCommand.git",
            from: "1.2.0"
        ), 
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.53.9"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "1.0.0-alpha"),
    ],
    targets: [
        .executableTarget(
            name: "peregrine",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftCommand", package: "SwiftCommand"),
                .product(name: "Puppy", package: "Puppy"),
                .product(name: "Lifecycle", package: "swift-service-lifecycle")
            ]
        ),
        .testTarget(name: "PeregrineTests", dependencies: ["peregrine"])
    ]
)
