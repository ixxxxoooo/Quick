// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleDevTools",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleDevTools", targets: ["ModuleDevTools"]),
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
    ],
    targets: [
        .target(name: "ModuleDevTools", dependencies: ["QuickCore", "QuickUI"]),
    ]
)
