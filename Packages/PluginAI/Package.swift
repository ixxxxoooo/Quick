// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginAI",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PluginAI", targets: ["PluginAI"])],
    dependencies: [
        .package(path: "../QuickCore"), .package(path: "../QuickUI"), .package(path: "../QuickPlatform")
    ],
    targets: [
        .target(name: "PluginAI", dependencies: ["QuickCore", "QuickUI", "QuickPlatform"]),
        .testTarget(
            name: "PluginAITests",
            // QuickCore 是必需的：契约测试要断言返回的 SearchableItem
            dependencies: ["PluginAI", "QuickCore"]
        )
    ]
)
