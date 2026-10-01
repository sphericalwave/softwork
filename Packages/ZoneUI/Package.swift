// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZoneUI",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ZoneUI", targets: ["ZoneUI"]),
    ],
    dependencies: [
        .package(path: "../SessionEngine"),
    ],
    targets: [
        .target(name: "ZoneUI", dependencies: ["SessionEngine"]),
    ]
)
