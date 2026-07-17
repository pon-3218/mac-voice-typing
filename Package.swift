// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VoiceInputLocal",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "VoiceInputLocal",
            path: "Sources/VoiceInputLocal",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VoiceInputLocalTests",
            dependencies: ["VoiceInputLocal"],
            path: "Tests/VoiceInputLocalTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
