// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecretsKit",
    platforms: [
        .iOS(.v13),
        .watchOS(.v6),
        .macOS(.v12)
    ],
    products: [
        .library(name: "SecretsRuntime", targets: ["SecretsRuntime"]),
        .executable(name: "secretcompiler", targets: ["SecretCompiler"])
    ],
    targets: [
        .target(
            name: "SecretsRuntime",
            dependencies: []
        ),
        .executableTarget(
            name: "SecretCompiler",
            dependencies: ["SecretsRuntime"]
        )
    ]
)
