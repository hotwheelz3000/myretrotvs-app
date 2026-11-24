// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyRetroTVs",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "MyRetroTVs",
            targets: ["MyRetroTVs"]
        ),
    ],
    dependencies: [
        // Generates typed Swift (L10n.helloWorld) from the strings in
        // Sources/<App>/Resources at build time. Config: Sources/<App>/swiftgen.yml.
        .package(url: "https://github.com/SwiftGen/SwiftGenPlugin", from: "6.6.2"),
    ],
    targets: [
        .target(
            name: "MyRetroTVs",
            exclude: ["swiftgen.yml"],
            resources: [
                .process("Resources"),
            ],
            plugins: [
                .plugin(name: "SwiftGenPlugin", package: "SwiftGenPlugin"),
            ]
        ),
    ]
)
