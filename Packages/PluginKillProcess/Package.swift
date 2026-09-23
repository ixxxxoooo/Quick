// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginKillProcess",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginKillProcess", targets: ["PluginKillProcess"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(
            name: "PluginKillProcess",
            dependencies: ["QuickCore", "QuickUI"]
        ),
        .testTarget(name: "PluginKillProcessTests", dependencies: ["PluginKillProcess"])
    ]
)
