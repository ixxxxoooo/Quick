// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginWordCounter",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginWordCounter", targets: ["PluginWordCounter"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginWordCounter", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginWordCounterTests", dependencies: ["PluginWordCounter"])
    ]
)
