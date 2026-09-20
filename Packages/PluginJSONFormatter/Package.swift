// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginJSONFormatter",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginJSONFormatter", targets: ["PluginJSONFormatter"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginJSONFormatter", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginJSONFormatterTests", dependencies: ["PluginJSONFormatter"])
    ]
)
