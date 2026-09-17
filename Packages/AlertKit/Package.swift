// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AlertKit",
    // macOS floor declared for dependency resolution only — AlertKit is
    // iOS-only in practice, gated via #if os(iOS) and an app-target
    // Frameworks platform filter.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AlertKit", targets: ["AlertKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sphericalwave/WorkoutAudioKit.git", branch: "main"),
    ],
    targets: [
        .target(name: "AlertKit", dependencies: ["WorkoutAudioKit"]),
    ]
)
