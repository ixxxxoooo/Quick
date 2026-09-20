// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginScreenshot",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PluginScreenshot", targets: ["PluginScreenshot"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [
        .target(name: "PluginScreenshot", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(
            name: "PluginScreenshotTests",
            dependencies: ["PluginScreenshot", "QuickCore"]
        )
    ]
)
