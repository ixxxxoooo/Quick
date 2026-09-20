// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleAI",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ModuleAI", targets: ["ModuleAI"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI"), .package(path: "../QuickPlatform")],
    targets: [.target(name: "ModuleAI", dependencies: ["QuickCore", "QuickUI", "QuickPlatform"])]
)
