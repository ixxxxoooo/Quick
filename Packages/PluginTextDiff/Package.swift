// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginTextDiff",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginTextDiff", targets: ["PluginTextDiff"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginTextDiff", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginTextDiffTests", dependencies: ["PluginTextDiff"])
    ]
)
