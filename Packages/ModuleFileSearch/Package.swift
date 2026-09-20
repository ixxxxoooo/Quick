// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleFileSearch",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleFileSearch", targets: ["ModuleFileSearch"]),
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
    ],
    targets: [
        .target(name: "ModuleFileSearch", dependencies: ["QuickCore", "QuickUI"]),
    ]
)
