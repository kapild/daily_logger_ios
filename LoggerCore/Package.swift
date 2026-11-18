// swift-tools-version:5.9
import PackageDescription

// The rules of Daily Logger with no iOS frameworks, so they build and are
// tested on any machine (CI runs the tests on Linux).
let package = Package(
    name: "LoggerCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "LoggerCore", targets: ["LoggerCore"])],
    targets: [
        .target(name: "LoggerCore"),
        .testTarget(name: "LoggerCoreTests", dependencies: ["LoggerCore"]),
    ]
)
