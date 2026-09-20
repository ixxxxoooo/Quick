// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginWindowManager",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PluginWindowManager", targets: ["PluginWindowManager"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [.target(name: "PluginWindowManager", dependencies: ["QuickCore", "QuickUI"])]
)
