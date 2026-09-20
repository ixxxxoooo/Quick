// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginHashCalculator",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginHashCalculator", targets: ["PluginHashCalculator"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginHashCalculator", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginHashCalculatorTests", dependencies: ["PluginHashCalculator"])
    ]
)
