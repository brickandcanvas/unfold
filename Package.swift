// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Unfold",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Unfold", path: "Sources/Unfold")
    ]
)
