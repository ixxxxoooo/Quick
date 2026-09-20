// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleLauncher",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleLauncher", targets: ["ModuleLauncher"]),
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform"),
    ],
    targets: [
        .target(
            name: "ModuleLauncher",
            dependencies: ["QuickCore", "QuickUI", "QuickPlatform"]
        ),
        .testTarget(name: "ModuleLauncherTests", dependencies: ["ModuleLauncher"]),
    ]
)
