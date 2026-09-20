// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleCalendar",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ModuleCalendar", targets: ["ModuleCalendar"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [.target(name: "ModuleCalendar", dependencies: ["QuickCore", "QuickUI"])]
)
