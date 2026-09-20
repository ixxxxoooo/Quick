// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleOCR",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleOCR", targets: ["ModuleOCR"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "ModuleOCR", dependencies: ["QuickCore", "QuickUI"])
    ]
)
