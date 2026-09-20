// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginOCR",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginOCR", targets: ["PluginOCR"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginOCR", dependencies: ["QuickCore", "QuickUI"])
    ]
)
