// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanMyCrap",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "CleanMyCrap",
            path: "Sources/CleanMyCrap",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
