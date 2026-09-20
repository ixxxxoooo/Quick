// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleSnippets",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleSnippets", targets: ["ModuleSnippets"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform")
    ],
    targets: [
        .target(name: "ModuleSnippets", dependencies: ["QuickCore", "QuickUI", "QuickPlatform"])
    ]
)
