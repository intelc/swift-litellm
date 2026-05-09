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
        .library(name: "LiteLLMLocalInference", targets: ["LiteLLMLocalInference"]),
    ],
    targets: [
        .target(
            name: "LiteLLM",
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "LiteLLMLocalInference",
            dependencies: ["LiteLLM"]
        ),
        .testTarget(
            name: "LiteLLMTests",
            dependencies: ["LiteLLM", "LiteLLMLocalInference"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
