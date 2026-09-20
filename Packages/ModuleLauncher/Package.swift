// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleLauncher",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleLauncher", targets: ["ModuleLauncher"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform")
    ],
    targets: [
        .target(
            name: "ModuleLauncher",
            dependencies: ["QuickCore", "QuickUI", "QuickPlatform"]
        ),
        .testTarget(
            name: "ModuleLauncherTests",
            // QuickPlatform 是必需的：LauncherModule 的公开初始化器接收 AppIndex，
            // 测试要构造模块就得能看到这个类型。
            dependencies: ["ModuleLauncher", "QuickPlatform"]
        )
    ]
)
