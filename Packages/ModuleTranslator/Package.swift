// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleTranslator",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleTranslator", targets: ["ModuleTranslator"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "ModuleTranslator", dependencies: ["QuickCore", "QuickUI"])
    ]
)
