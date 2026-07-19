// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VoiceInputLocal",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "VoiceInputLocal",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/VoiceInputLocal",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "VoiceInputLocalTests",
            dependencies: ["VoiceInputLocal"],
            path: "Tests/VoiceInputLocalTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
