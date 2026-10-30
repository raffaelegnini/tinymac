// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TinyMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TinyMac", targets: ["TinyMac"]),
        .executable(name: "TinyMacPlus", targets: ["TinyMacPlus"]),
    ],
    targets: [
        // The TinyTask 1.77 engine, shared by both apps.
        .target(
            name: "TinyMacCore",
            path: "Sources/TinyMacCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        // TinyMac: the 1:1 port. Nothing but the engine.
        .executableTarget(name: "TinyMac", dependencies: ["TinyMacCore"], path: "Sources/TinyMac"),
        // TinyMac Plus: the same engine with optional extras.
        .executableTarget(name: "TinyMacPlus", dependencies: ["TinyMacCore"], path: "Sources/TinyMacPlus"),
        .testTarget(name: "TinyMacCoreTests", dependencies: ["TinyMacCore"], path: "Tests/TinyMacCoreTests"),
    ]
)
