// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatsKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "StatsKit", targets: ["StatsKit"]),
    ],
    targets: [
        .target(name: "StatsKit"),
    ]
)
