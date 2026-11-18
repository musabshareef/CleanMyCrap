// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanMyCrap",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "CleanMyCrap", targets: ["CleanMyCrap"]),
        .executable(name: "crap", targets: ["crap"]),
    ],
    targets: [
        // The scanning and eviction engine, shared by the app and the CLI. No UI.
        .target(
            name: "CrapCore",
            path: "Sources/CrapCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CleanMyCrap",
            dependencies: ["CrapCore"],
            path: "Sources/CleanMyCrap",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "crap",
            dependencies: ["CrapCore"],
            path: "Sources/crap",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
