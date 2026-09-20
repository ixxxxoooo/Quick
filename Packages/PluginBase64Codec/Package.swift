// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginBase64Codec",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginBase64Codec", targets: ["PluginBase64Codec"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginBase64Codec", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginBase64CodecTests", dependencies: ["PluginBase64Codec"])
    ]
)
