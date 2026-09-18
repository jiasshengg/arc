// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Arc",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Arc", targets: ["Arc"])],
    targets: [
        .target(name: "ArcCore"),
        .executableTarget(name: "Arc", dependencies: ["ArcCore"]),
        .testTarget(name: "ArcCoreTests", dependencies: ["ArcCore"]),
        .testTarget(name: "ArcTests", dependencies: ["Arc"])
    ]
)
