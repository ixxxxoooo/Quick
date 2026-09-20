// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleNetworkTools",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ModuleNetworkTools", targets: ["ModuleNetworkTools"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [.target(name: "ModuleNetworkTools", dependencies: ["QuickCore", "QuickUI"])]
)
