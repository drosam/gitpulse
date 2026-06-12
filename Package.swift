// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scout",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Scout",
            path: "Sources/Scout"
        )
    ]
)
