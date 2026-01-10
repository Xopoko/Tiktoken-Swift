// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tiktoken-Swift",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(name: "Tiktoken", targets: ["Tiktoken"]),
        .executable(name: "TiktokenBenchmark", targets: ["TiktokenBenchmark"])
    ],
    targets: [
        .target(
            name: "Tiktoken",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TiktokenBenchmark",
            dependencies: ["Tiktoken"]
        ),
        .testTarget(
            name: "TiktokenTests",
            dependencies: ["Tiktoken"]
        )
    ],
    swiftLanguageModes: [.v6]
)
