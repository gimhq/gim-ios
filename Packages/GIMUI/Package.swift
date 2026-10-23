// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GIMUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "GIMUI", targets: ["GIMUI"]),
        // The gim-core bridge and the platform hooks without SwiftUI, for the Notification Service Extension.
        .library(name: "GIMPlatform", targets: ["GIMPlatform"]),
    ],
    dependencies: [
        .package(path: "../GIMKit"),
        .package(path: "../../Vendor/GIMCore"),
    ],
    targets: [
        .target(
            name: "GIMPlatform",
            dependencies: [
                .product(name: "GIMClientKit", package: "GIMKit"),
                .product(name: "GIMCore", package: "GIMCore"),
            ]
        ),
        .target(
            name: "GIMUI",
            dependencies: [
                "GIMPlatform",
                .product(name: "GIMClientKit", package: "GIMKit"),
                .product(name: "GIMFeatures", package: "GIMKit"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "GIMUITests", dependencies: ["GIMUI", "GIMPlatform"]),
    ]
)
