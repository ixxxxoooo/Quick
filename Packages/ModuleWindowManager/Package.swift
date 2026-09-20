// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleWindowManager",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ModuleWindowManager", targets: ["ModuleWindowManager"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [.target(name: "ModuleWindowManager", dependencies: ["QuickCore", "QuickUI"])]
)
