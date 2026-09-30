// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpaceGuard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SpaceGuard",
            path: "Sources/SpaceGuard"
        )
    ]
)
