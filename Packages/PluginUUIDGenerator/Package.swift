// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginUUIDGenerator",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginUUIDGenerator", targets: ["PluginUUIDGenerator"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginUUIDGenerator", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginUUIDGeneratorTests", dependencies: ["PluginUUIDGenerator"])
    ]
)
