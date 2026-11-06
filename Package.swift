// swift-tools-version:5.10
// Core networking / model layer as a Swift package so it can be unit tested with `swift test`
// (on macOS CI and on Linux). The iOS app itself is generated from project.yml with XcodeGen.
import PackageDescription

let package = Package(
    name: "AxonCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AxonCore", targets: ["AxonCore"]),
    ],
    targets: [
        .target(
            name: "AxonCore",
            path: "Axon",
            exclude: ["App", "Features", "UI", "Resources", "Core/Keychain.swift"],
            sources: [
                "Core/JSONValue.swift",
                "Core/Formatting.swift",
                "Core/APIClient.swift",
                "Models",
                "Services",
            ]
        ),
        .testTarget(
            name: "AxonCoreTests",
            dependencies: ["AxonCore"],
            path: "Tests/AxonCoreTests"
        ),
    ]
)
