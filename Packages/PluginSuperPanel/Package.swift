// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginSuperPanel",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginSuperPanel", targets: ["PluginSuperPanel"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform")
    ],
    targets: [
        .target(
            name: "PluginSuperPanel",
            dependencies: ["QuickCore", "QuickUI", "QuickPlatform"]
        ),
        .testTarget(name: "PluginSuperPanelTests", dependencies: ["PluginSuperPanel"])
    ]
)
