// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tidy",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Tidy",
            path: "Sources/Tidy",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
