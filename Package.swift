// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenLadderStudio",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LadderCore", targets: ["LadderCore"])],
    targets: [
        .target(name: "LadderCore"),
        .testTarget(name: "LadderCoreTests", dependencies: ["LadderCore"])
    ]
)
