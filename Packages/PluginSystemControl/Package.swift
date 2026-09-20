// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginSystemControl",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginSystemControl", targets: ["PluginSystemControl"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginSystemControl", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginSystemControlTests", dependencies: ["PluginSystemControl"])
    ]
)
