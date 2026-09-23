// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "QuickUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "QuickUI", targets: ["QuickUI"])
    ],
    dependencies: [
        .package(path: "../QuickCore"),
        .package(path: "../QuickPlatform"),
    ],
    targets: [
        .target(
            name: "QuickUI",
            dependencies: ["QuickCore", "QuickPlatform"]
        ),
        .testTarget(name: "QuickUITests", dependencies: ["QuickUI"])
    ]
)
