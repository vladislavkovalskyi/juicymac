// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JuicyKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "JuicyCore", targets: ["JuicyCore"]),
        .library(name: "JuicySystem", targets: ["JuicySystem"]),
        .library(name: "JuicyHelperKit", targets: ["JuicyHelperKit"]),
    ],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "JuicyCore"),
        .target(
            name: "JuicySystem",
            dependencies: ["CSMC", "JuicyCore"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit")]
        ),
        .target(name: "JuicyHelperKit", dependencies: ["CSMC", "JuicySystem"]),
        .testTarget(name: "JuicyCoreTests", dependencies: ["JuicyCore"]),
        .testTarget(name: "JuicySystemTests", dependencies: ["JuicySystem", "JuicyCore"]),
    ]
)
