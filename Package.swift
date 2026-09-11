// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CloseFadeIn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CloseFadeIn", path: "Sources/CloseFadeIn")
    ]
)
