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
        .target(name: "PluginTranslator", dependencies: ["QuickCore", "QuickUI"]),
        // QuickCore 是必需的：契约测试要用 SearchableItem 这个类型接住搜索结果
        .testTarget(
            name: "PluginTranslatorTests",
            dependencies: ["PluginTranslator", "QuickCore"]
        )
    ]
)
