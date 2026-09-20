// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleSystemMonitor",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ModuleSystemMonitor", targets: ["ModuleSystemMonitor"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [.target(name: "ModuleSystemMonitor", dependencies: ["QuickCore", "QuickUI"])]
)
