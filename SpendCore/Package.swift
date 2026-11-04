// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpendCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14), // only so `swift test` runs on the Mac
    ],
    products: [
        .library(name: "SpendCore", targets: ["SpendCore"]),
    ],
    targets: [
        .target(
            name: "SpendCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SpendCoreTests",
            dependencies: ["SpendCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
