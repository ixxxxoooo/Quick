// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginTimestampConverter",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginTimestampConverter", targets: ["PluginTimestampConverter"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginTimestampConverter", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginTimestampConverterTests", dependencies: ["PluginTimestampConverter"])
    ]
)
