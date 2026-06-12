// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecretsKit",
    platforms: [
        .iOS(.v14),
        .watchOS(.v7),
        .macOS(.v11)
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
        ),
        .testTarget(
            name: "SecretsRuntimeTests",
            dependencies: ["SecretsRuntime"]
        ),
        .testTarget(
            name: "SecretCompilerTests",
            dependencies: ["SecretCompiler"]
        )
    ]
)
