// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginLauncher",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginLauncher", targets: ["PluginLauncher"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform")
    ],
    targets: [
        .target(
            name: "PluginLauncher",
            dependencies: ["QuickCore", "QuickUI", "QuickPlatform"]
        ),
        .testTarget(
            name: "PluginLauncherTests",
            // QuickPlatform 是必需的：LauncherPlugin 的公开初始化器接收 AppIndex，
            // 测试要构造插件就得能看到这个类型。
            dependencies: ["PluginLauncher", "QuickPlatform"]
        )
    ]
)
