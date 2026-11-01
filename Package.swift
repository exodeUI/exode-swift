// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "ExodeUI",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "ExodeUI",
            targets: ["ExodeUI"]
        ),
    ],
    targets: [
        .target(
            name: "ExodeUI",
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(
            name: "ExodeUITests",
            dependencies: ["ExodeUI"],
            resources: [
                .copy("Fixtures/demo.bexode"),
                .copy("Fixtures/demo.exode"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
