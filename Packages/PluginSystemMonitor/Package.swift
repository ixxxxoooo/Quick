// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginSystemMonitor",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PluginSystemMonitor", targets: ["PluginSystemMonitor"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [
        .target(name: "PluginSystemMonitor", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(
            name: "PluginSystemMonitorTests",
            dependencies: ["PluginSystemMonitor", "QuickCore"]
        )
    ]
)
