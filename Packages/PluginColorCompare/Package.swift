// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginColorCompare",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginColorCompare", targets: ["PluginColorCompare"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginColorCompare", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginColorCompareTests", dependencies: ["PluginColorCompare"])
    ]
)
