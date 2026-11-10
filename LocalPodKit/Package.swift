// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalPodKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LocalPodKit", targets: ["LocalPodKit"])
    ],
    targets: [
        .target(name: "LocalPodKit"),
        .testTarget(name: "LocalPodKitTests", dependencies: ["LocalPodKit"])
    ]
)
