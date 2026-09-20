// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginTranslator",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginTranslator", targets: ["PluginTranslator"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginTranslator", dependencies: ["QuickCore", "QuickUI"])
    ]
)
