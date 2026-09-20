// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginCalendar",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PluginCalendar", targets: ["PluginCalendar"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [
        .target(name: "PluginCalendar", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(
            name: "PluginCalendarTests",
            // QuickCore 是必需的：契约测试要断言返回的 SearchableItem
            dependencies: ["PluginCalendar", "QuickCore"]
        )
    ]
)
