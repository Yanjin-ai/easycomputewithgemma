// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GemmaHostMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "GemmaHostMac", targets: ["GemmaHostMac"])
    ],
    targets: [
        .target(
            name: "GemmaHostMac",
            path: "GemmaHostMac",
            exclude: ["Info.plist"]
        )
    ]
)
