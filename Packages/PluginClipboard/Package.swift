// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginClipboard",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginClipboard", targets: ["PluginClipboard"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform")
    ],
    targets: [
        .target(
            name: "PluginClipboard",
            dependencies: ["QuickCore", "QuickUI", "QuickPlatform"]
        ),
        .testTarget(name: "PluginClipboardTests", dependencies: ["PluginClipboard"])
    ]
)
