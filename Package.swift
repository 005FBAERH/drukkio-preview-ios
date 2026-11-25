// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrukkioPreview",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "DrukkioPreview",
            targets: ["DrukkioPreview"]
        ),
    ],
    targets: [
        .target(
            name: "DrukkioPreview",
            path: "Sources/DrukkioPreview"
        ),
    ]
)
