// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanMyCrap",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "CleanMyCrap", targets: ["CleanMyCrap"]),
        .executable(name: "crap", targets: ["crap"]),
    ],
    dependencies: [
        // In-app updates. Free and open source; the standard updater for Mac apps outside the App Store.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
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
            dependencies: ["CrapCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/CleanMyCrap",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework is embedded in Contents/Frameworks of the app bundle.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "crap",
            dependencies: ["CrapCore"],
            path: "Sources/crap",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
