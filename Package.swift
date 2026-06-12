// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GHPulse",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "GHPulse",
            path: "Sources/GHPulse"
        )
    ]
)
