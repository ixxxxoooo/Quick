// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginDevTools",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginDevTools", targets: ["PluginDevTools"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginDevTools", dependencies: ["QuickCore", "QuickUI"])
    ]
)
