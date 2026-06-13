// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitPulse",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "GitPulse",
            path: "Sources/GitPulse"
        )
    ]
)
