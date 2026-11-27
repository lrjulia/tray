// swift-tools-version:5.9
// `swift run` launches Tray straight from Terminal for quick iteration.
// For a real .app bundle (menu-bar only, proper permissions), use project.yml with XcodeGen.
import PackageDescription

let package = Package(
    name: "Tray",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tray", path: "Sources/Tray")
    ]
)
