// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIWorkbench",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AIWorkbench",
            path: "Sources/AIWorkbench"
        )
    ],
    swiftLanguageVersions: [.v5]
)
