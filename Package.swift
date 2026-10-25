// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AgentSweep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentSweep", targets: ["AgentSweep"]),
        .library(name: "AgentSweepCore", targets: ["AgentSweepCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "AgentSweepCore",
            resources: [.copy("Resources/rules.json")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "AgentSweep",
            dependencies: ["AgentSweepCore", .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework ships in AgentSweep.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "AgentSweepCoreTests", dependencies: ["AgentSweepCore"]),
    ]
)
