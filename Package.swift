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
        ),
        .testTarget(
            name: "TidyTests",
            dependencies: ["Tidy"],
            path: "Tests/TidyTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
