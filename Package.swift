// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SheepFence",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "SheepFence", targets: ["SheepFence"])],
    targets: [
        .target(name: "SheepFence", exclude: ["Storage/README.md"]),
        .testTarget(
            name: "SheepFenceTests",
            dependencies: ["SheepFence"],
            resources: [.process("Fixtures")]
        ),
    ]
)
