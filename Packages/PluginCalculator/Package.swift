// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginCalculator",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginCalculator", targets: ["PluginCalculator"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginCalculator", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginCalculatorTests", dependencies: ["PluginCalculator"])
    ]
)
