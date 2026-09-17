// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloudSync",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CloudSync", targets: ["CloudSync"]),
    ],
    dependencies: [
        .package(path: "../Persistence"),
    ],
    targets: [
        .target(name: "CloudSync", dependencies: ["Persistence"]),
    ]
)
