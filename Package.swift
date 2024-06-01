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
    ],
    targets: [
        .executableTarget(
            name: "peregrine",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftCommand", package: "SwiftCommand")
            ]
        ),
    ]
)
