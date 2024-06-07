// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "peregrine",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(
            url: "https://github.com/Zollerboy1/SwiftCommand.git",
            from: "1.2.0"
        ), 
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.53.9"),
    ],
    targets: [
        .executableTarget(
            name: "Peregrine",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftCommand", package: "SwiftCommand")
            ]
        ),
        .testTarget(name: "PeregrineTests", dependencies: ["Peregrine"])
    ]
)
