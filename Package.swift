// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AgentSweep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentSweep", targets: ["AgentSweep"]),
        .library(name: "AgentSweepCore", targets: ["AgentSweepCore"]),
    ],
    targets: [
        .target(
            name: "AgentSweepCore",
            resources: [.copy("Resources/rules.json")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "AgentSweep", dependencies: ["AgentSweepCore"]),
        .testTarget(name: "AgentSweepCoreTests", dependencies: ["AgentSweepCore"]),
    ]
)
