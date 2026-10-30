// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TinyMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TinyMac",
            path: "Sources/TinyMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
