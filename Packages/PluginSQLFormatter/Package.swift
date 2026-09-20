// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginSQLFormatter",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginSQLFormatter", targets: ["PluginSQLFormatter"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginSQLFormatter", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginSQLFormatterTests", dependencies: ["PluginSQLFormatter"])
    ]
)
