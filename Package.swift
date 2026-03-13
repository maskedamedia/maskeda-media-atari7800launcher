// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "prosystem-macos-launcher",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Atari7800Launcher", targets: ["Atari7800Launcher"]),
    ],
    targets: [
        .target(
            name: "CLibretroBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "Input",
            dependencies: ["CLibretroBridge"]
        ),
        .target(
            name: "Audio",
            dependencies: []
        ),
        .target(
            name: "Renderer",
            dependencies: ["Input"]
        ),
        .target(
            name: "CoreHost",
            dependencies: ["CLibretroBridge", "Audio", "Input", "Renderer"]
        ),
        .target(
            name: "UI",
            dependencies: ["CoreHost", "Renderer", "Input"]
        ),
        .executableTarget(
            name: "Atari7800Launcher",
            dependencies: ["UI", "CoreHost"]
        ),
    ]
)
