// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleScreenshot",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ModuleScreenshot", targets: ["ModuleScreenshot"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [.target(name: "ModuleScreenshot", dependencies: ["QuickCore", "QuickUI"])]
)
