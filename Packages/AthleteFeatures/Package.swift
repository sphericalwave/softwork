// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AthleteFeatures",
    // macOS floor declared for dependency resolution only — AthleteFeatures
    // is iOS-only in practice, gated via #if os(iOS) and an app-target
    // Frameworks platform filter.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AthleteFeatures", targets: ["AthleteFeatures"]),
    ],
    dependencies: [
        .package(path: "../SessionEngine"),
        .package(path: "../RulesKit"),
        .package(path: "../PlanningKit"),
        .package(path: "../Persistence"),
        .package(path: "../PeerKit"),
        .package(path: "../AlertKit"),
    ],
    targets: [
        .target(
            name: "AthleteFeatures",
            dependencies: ["SessionEngine", "RulesKit", "PlanningKit", "Persistence", "PeerKit", "AlertKit"]
        ),
    ]
)
