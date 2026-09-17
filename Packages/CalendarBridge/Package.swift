// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarBridge",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CalendarBridge", targets: ["CalendarBridge"]),
    ],
    dependencies: [
        .package(path: "../PlanningKit"),
    ],
    targets: [
        .target(name: "CalendarBridge", dependencies: ["PlanningKit"]),
    ]
)
