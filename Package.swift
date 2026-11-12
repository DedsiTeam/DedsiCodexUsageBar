// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DedsiCodexUsageBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DedsiCodexUsageBar",
            path: "Sources/DedsiCodexUsageBar",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
