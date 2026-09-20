// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginNetworkTools",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PluginNetworkTools", targets: ["PluginNetworkTools"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [.target(name: "PluginNetworkTools", dependencies: ["QuickCore", "QuickUI"])]
)
