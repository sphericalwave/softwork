// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PeerKit",
    // macOS floor declared for dependency resolution only — PeerKit is
    // iOS-only in practice (live sparring is iPhone/iPad, non-goal §1.1),
    // gated via #if os(iOS) and an app-target Frameworks platform filter.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PeerKit", targets: ["PeerKit"]),
    ],
    dependencies: [
        .package(path: "../SessionEngine"),
    ],
    targets: [
        .target(name: "PeerKit", dependencies: ["SessionEngine"]),
    ]
)
