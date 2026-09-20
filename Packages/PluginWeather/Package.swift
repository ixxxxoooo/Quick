// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginWeather",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PluginWeather", targets: ["PluginWeather"])],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform")
    ],
    targets: [
        .target(
            name: "PluginWeather",
            dependencies: ["QuickCore", "QuickUI", "QuickPlatform"]
        )
    ]
)
