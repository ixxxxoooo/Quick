// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginSnippets",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginSnippets", targets: ["PluginSnippets"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform")
    ],
    targets: [
        .target(name: "PluginSnippets", dependencies: ["QuickCore", "QuickUI", "QuickPlatform"])
    ]
)
