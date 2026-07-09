// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MinimalReport",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MinimalReport", targets: ["MinimalReport"])
    ],
    targets: [
        .executableTarget(
            name: "MinimalReport",
            path: "Sources/MinimalReport",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
