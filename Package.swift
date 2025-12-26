// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HertzBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HertzBridge", targets: ["HertzBridge"]),
        .library(name: "HertzBridgeCore", targets: ["HertzBridgeCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HertzBridgeCore",
            dependencies: [],
            path: "Sources/HertzBridgeCore",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "HertzBridge",
            dependencies: ["HertzBridgeCore"],
            path: "Sources/HertzBridge"
        ),
        .testTarget(
            name: "HertzBridgeTests",
            dependencies: ["HertzBridgeCore"],
            path: "Tests/HertzBridgeTests"
        )
    ]
)
