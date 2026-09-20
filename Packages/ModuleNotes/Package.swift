// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleNotes",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ModuleNotes", targets: ["ModuleNotes"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI"), .package(path: "../QuickPlatform")],
    targets: [.target(name: "ModuleNotes", dependencies: ["QuickCore", "QuickUI", "QuickPlatform"])]
)
