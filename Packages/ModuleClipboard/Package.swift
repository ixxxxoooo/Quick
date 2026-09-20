// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleClipboard",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleClipboard", targets: ["ModuleClipboard"]),
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform"),
    ],
    targets: [
        .target(
            name: "ModuleClipboard",
            dependencies: ["QuickCore", "QuickUI", "QuickPlatform"]
        ),
        .testTarget(name: "ModuleClipboardTests", dependencies: ["ModuleClipboard"]),
    ]
)
