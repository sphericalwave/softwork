// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SessionEngine", targets: ["SessionEngine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sphericalwave/HeartRateKit.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "SessionEngine",
            dependencies: [
                .product(name: "HeartRateCore", package: "HeartRateKit"),
            ]
        ),
        .testTarget(name: "SessionEngineTests", dependencies: ["SessionEngine"]),
    ]
)
