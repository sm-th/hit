// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hit",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Hit", targets: ["Hit"])],
    targets: [
        .target(name: "HitCore"),
        .executableTarget(name: "Hit", dependencies: ["HitCore"]),
        .testTarget(name: "HitCoreTests", dependencies: ["HitCore"])
    ]
)
