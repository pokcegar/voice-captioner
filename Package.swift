// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "voice-captioner",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "VoiceCaptionerCore", targets: ["VoiceCaptionerCore"]),
        .executable(name: "voice-captioner-app", targets: ["VoiceCaptionerApp"]),
        .executable(name: "microphone-smoke", targets: ["MicrophoneSmoke"]),
        .executable(name: "system-audio-smoke", targets: ["SystemAudioSmoke"]),
        .executable(name: "dual-capture-smoke", targets: ["DualCaptureSmoke"]),
        .executable(name: "unified-capture-smoke", targets: ["UnifiedCaptureSmoke"])
    ],
    targets: [
        .target(
            name: "VoiceCaptionerCore"
        ),
        .executableTarget(
            name: "VoiceCaptionerApp",
            dependencies: ["VoiceCaptionerCore"]
        ),
        .executableTarget(
            name: "MicrophoneSmoke",
            dependencies: ["VoiceCaptionerCore"]
        ),
        .executableTarget(
            name: "SystemAudioSmoke",
            dependencies: ["VoiceCaptionerCore"]
        ),
        .executableTarget(
            name: "DualCaptureSmoke",
            dependencies: ["VoiceCaptionerCore"]
        ),
        .executableTarget(
            name: "UnifiedCaptureSmoke",
            dependencies: ["VoiceCaptionerCore"]
        ),
        .testTarget(
            name: "VoiceCaptionerCoreTests",
            dependencies: ["VoiceCaptionerCore"]
        )
    ]
)
