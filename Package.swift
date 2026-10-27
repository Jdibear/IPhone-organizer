// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tidy",
    // The iPhone app (TidyiOS.xcodeproj) compiles Sources/Shared too.
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Tidy",
            path: "Sources",
            sources: ["Tidy", "Shared"],
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
