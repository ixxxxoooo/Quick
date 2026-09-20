// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "ModuleWeather",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ModuleWeather", targets: ["ModuleWeather"])],
    dependencies: [.package(path: "../QuickCore"), .package(path: "../QuickUI")],
    targets: [.target(name: "ModuleWeather", dependencies: ["QuickCore", "QuickUI"])]
)
