// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitPulse",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "GitPulseCore",
            path: "Sources/GitPulseCore"
        ),
        .executableTarget(
            name: "GitPulse",
            dependencies: ["GitPulseCore"],
            path: "Sources/GitPulse"
        ),
        .testTarget(
            name: "GitPulseCoreTests",
            dependencies: ["GitPulseCore"],
            path: "Tests/GitPulseCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
