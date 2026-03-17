// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "osc-runner",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/taylorcjensen/OSCFoundation.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "osc-runner",
            dependencies: ["OSCFoundation"],
            path: "Sources"
        ),
    ]
)
