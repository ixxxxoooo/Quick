// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginNotes",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PluginNotes", targets: ["PluginNotes"])],
    dependencies: [
        .package(path: "../QuickCore"), .package(path: "../QuickUI"), .package(path: "../QuickPlatform")
    ],
    targets: [.target(name: "PluginNotes", dependencies: ["QuickCore", "QuickUI", "QuickPlatform"])]
)
