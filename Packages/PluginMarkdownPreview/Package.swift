// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "PluginMarkdownPreview",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PluginMarkdownPreview", targets: ["PluginMarkdownPreview"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "PluginMarkdownPreview", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "PluginMarkdownPreviewTests", dependencies: ["PluginMarkdownPreview"])
    ]
)
