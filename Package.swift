// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "peregrine",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/sushichop/Puppy", from: "0.7.0"),
        .package(
            url: "https://github.com/Zollerboy1/SwiftCommand.git",
            from: "1.2.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "peregrine",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftCommand", package: "SwiftCommand"),
                .product(name: "Puppy", package: "Puppy"),
            ]
        ),
        .testTarget(name: "PeregrineTests", dependencies: ["peregrine"]),
    ]
)
