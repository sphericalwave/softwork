// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlanningKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PlanningKit", targets: ["PlanningKit"]),
    ],
    targets: [
        .target(name: "PlanningKit"),
    ]
)
