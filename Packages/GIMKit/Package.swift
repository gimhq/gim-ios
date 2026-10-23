// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GIMKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "GIMClientKit", targets: ["GIMClientKit"]),
        .library(name: "GIMFeatures", targets: ["GIMFeatures"]),
    ],
    targets: [
        .target(name: "GIMClientKit"),
        .target(name: "GIMFeatures", dependencies: ["GIMClientKit"], resources: [.process("Resources")]),
        .testTarget(name: "GIMClientKitTests", dependencies: ["GIMClientKit"]),
        .testTarget(name: "GIMFeaturesTests", dependencies: ["GIMFeatures"]),
    ]
)
