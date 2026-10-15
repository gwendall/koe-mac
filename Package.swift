// swift-tools-version:5.10
// Koe: hold a key, talk, the words land where you type. A menu bar app on
// Parakeet Ultra (Core ML, Apple Neural Engine) through FluidAudio, and, when
// asked, a small language model through llama.cpp to polish the words.
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
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio"), "llama"],
            path: "app/Sources",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // llama.cpp's own build for Apple (Metal), pinned.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11658/llama-b11658-xcframework.zip",
            checksum: "783cb907e3553e2621a58588901686294f92f9bdcf009868d24fc1169cb29bba"
        ),
    ]
)
