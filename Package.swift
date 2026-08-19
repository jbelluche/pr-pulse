// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PRPulse",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "PRPulse", targets: ["PRPulse"]),
    ],
    targets: [
        .executableTarget(name: "PRPulse"),
        .testTarget(name: "PRPulseTests", dependencies: ["PRPulse"]),
    ]
)
