// swift-tools-version: 5.9
import PackageDescription

// The playground is a separate package so the shipped ExodeUI package stays
// dependency-free and `swift test` in `packages/swift` stays fast. It consumes
// the parent package through a local path dependency.
let package = Package(
    name: "ExodePlayground",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "ExodePlayground", targets: ["ExodePlayground"]),
        .executable(name: "ExodeSmoke", targets: ["ExodeSmoke"]),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .target(
            name: "PlaygroundKit",
            dependencies: [
                .product(name: "ExodeUI", package: "swift"),
            ],
            resources: [
                .copy("Resources/Artboards"),
            ]
        ),
        .executableTarget(
            name: "ExodePlayground",
            dependencies: ["PlaygroundKit"]
        ),
        .executableTarget(
            name: "ExodeSmoke",
            dependencies: ["PlaygroundKit"]
        ),
    ]
)
