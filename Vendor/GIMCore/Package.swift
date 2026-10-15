// swift-tools-version: 6.0
import PackageDescription

// gim-core's UniFFI bindings, vendored by scripts/sync-gim-core.sh (version in GIM_CORE_VERSION).
// `GIMCoreFFI` is the C module inside the static-library xcframework; `GIMCore` is the generated Swift API.
let package = Package(
    name: "GIMCore",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "GIMCore", targets: ["GIMCore"])
    ],
    targets: [
        .binaryTarget(name: "GIMCoreFFI", path: "GIMCore.xcframework.zip"),
        .target(
            name: "GIMCore",
            dependencies: ["GIMCoreFFI"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // getrandom uses SecRandomCopyBytes on iOS.
            linkerSettings: [.linkedFramework("Security")]
        ),
    ]
)
