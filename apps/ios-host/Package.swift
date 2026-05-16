// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GemmaHost",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GemmaHost", targets: ["GemmaHost"])
    ],
    targets: [
        .target(
            name: "GemmaHost",
            path: "GemmaHost",
            exclude: ["Info.plist"]
        )
    ]
)
