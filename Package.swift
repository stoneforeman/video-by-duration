// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoByDuration",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VideoByDuration",
            path: "Sources/VideoByDuration"
        )
    ]
)
