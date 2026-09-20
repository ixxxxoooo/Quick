// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginURLCodec",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginURLCodec", targets: ["PluginURLCodec"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginURLCodec", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginURLCodecTests", dependencies: ["PluginURLCodec"])
    ]
)
