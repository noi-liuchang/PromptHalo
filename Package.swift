// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PromptHalo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PromptHalo", targets: ["PromptHalo"])
    ],
    targets: [
        .executableTarget(
            name: "PromptHalo",
            path: "Sources/PromptHalo",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
