// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "QuickCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "QuickCore", targets: ["QuickCore"])
    ],
    targets: [
        .target(name: "QuickCore"),
        .testTarget(name: "QuickCoreTests", dependencies: ["QuickCore"])
    ]
)
