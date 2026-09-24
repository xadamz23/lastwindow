// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LastWindow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LastWindowCore"),
        .executableTarget(name: "LastWindow", dependencies: ["LastWindowCore"]),
        .testTarget(name: "LastWindowCoreTests", dependencies: ["LastWindowCore"]),
    ]
)
