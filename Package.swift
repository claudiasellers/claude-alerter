// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeAlerter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeAlerter", path: "Sources/ClaudeAlerter")
    ]
)
