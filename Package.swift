// swift-tools-version:5.10
// Koe: hold a key, talk, the words land where you type. A menu bar app on
// Parakeet Ultra (Core ML, Apple Neural Engine) through FluidAudio.
import PackageDescription

let package = Package(
    name: "Koe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .executableTarget(
            name: "Koe",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "app/Sources"
        ),
    ]
)
