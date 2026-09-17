// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RulesKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RulesKit", targets: ["RulesKit"]),
    ],
    targets: [
        .target(name: "RulesKit"),
    ]
)
