// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-litellm",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LiteLLM", targets: ["LiteLLM"]),
    ],
    targets: [
        .target(
            name: "LiteLLM",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "LiteLLMTests",
            dependencies: ["LiteLLM"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
