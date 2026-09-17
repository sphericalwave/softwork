// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoachFeatures",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CoachFeatures", targets: ["CoachFeatures"]),
    ],
    dependencies: [
        .package(path: "../PlanningKit"),
        .package(path: "../StatsKit"),
        .package(path: "../Persistence"),
        .package(path: "../CloudSync"),
        .package(path: "../CalendarBridge"),
    ],
    targets: [
        .target(
            name: "CoachFeatures",
            dependencies: ["PlanningKit", "StatsKit", "Persistence", "CloudSync", "CalendarBridge"]
        ),
    ]
)
