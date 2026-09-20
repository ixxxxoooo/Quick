// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleSystemControl",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleSystemControl", targets: ["ModuleSystemControl"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")
    ],
    targets: [
        .target(name: "ModuleSystemControl", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "ModuleSystemControlTests", dependencies: ["ModuleSystemControl"])
    ]
)
