// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalPodKit",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LocalPodKit", targets: ["LocalPodKit"])
    ],
    targets: [
        .target(
            name: "LocalPodKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LocalPodKitTests",
            dependencies: ["LocalPodKit"],
            resources: [.process("Resources")]
        )
    ]
)
