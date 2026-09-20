// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleCalculator",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModuleCalculator", targets: ["ModuleCalculator"]),
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
    ],
    targets: [
        .target(name: "ModuleCalculator", dependencies: ["QuickCore", "QuickUI"]),
        .testTarget(name: "ModuleCalculatorTests", dependencies: ["ModuleCalculator"]),
    ]
)
