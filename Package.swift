// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ClaudeMetrics",
    defaultLocalization: nil,
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeMetrics",
            path: "Sources/ClaudeMetrics"
        )
    ]
)
