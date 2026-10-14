// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GIMUI",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "GIMUI", targets: ["GIMUI"])
    ],
    dependencies: [
        .package(path: "../GIMKit")
    ],
    targets: [
        .target(
            name: "GIMUI",
            dependencies: [
                .product(name: "GIMClientKit", package: "GIMKit"),
                .product(name: "GIMFeatures", package: "GIMKit"),
            ]
        ),
        .testTarget(name: "GIMUITests", dependencies: ["GIMUI"]),
    ]
)
