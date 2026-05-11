// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AEONRelay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AEONRelay",
            path: "Sources/AEONRelay"
        ),
        .testTarget(
            name: "AEONRelayTests",
            dependencies: ["AEONRelay"],
            path: "Tests/AEONRelayTests"
        )
    ]
)
