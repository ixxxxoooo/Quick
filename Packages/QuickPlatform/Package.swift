// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "QuickPlatform",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "QuickPlatform", targets: ["QuickPlatform"]),
    ],
    dependencies: [
        .package(path: "../QuickCore"),
    ],
    targets: [
        .target(
            name: "QuickPlatform",
            dependencies: ["QuickCore"]
        ),
        .testTarget(name: "QuickPlatformTests", dependencies: ["QuickPlatform"]),
    ]
)
