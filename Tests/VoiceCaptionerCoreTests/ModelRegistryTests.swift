import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("ModelRegistry")
struct ModelRegistryTests {
    @Test func listsDownloadedWhisperModels() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "ggml-base.bin"))
        try Data().write(to: root.appending(path: "notes.txt"))
        try Data().write(to: root.appending(path: "model.gguf"))

        let registry = ModelRegistry(modelsDirectory: root)
        let models = try registry.downloadedModels()

        #expect(models.map(\.name) == ["ggml-base", "model"])
    }

    @Test func ranksManifestBackedModelsByRecommendation() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for filename in ["ggml-tiny.bin", "ggml-base.bin", "ggml-small.bin", "ggml-medium.bin", "ggml-large-v3-turbo.bin", "ggml-large-v3.bin"] {
            try Data(filename.utf8).write(to: root.appending(path: filename))
            try manifest(filename: filename, status: "downloaded", sha256: "sha-\(filename)")
                .write(to: root.appending(path: "\(filename).manifest.json"), atomically: true, encoding: .utf8)
        }

        let registry = ModelRegistry(modelsDirectory: root)
        let entries = try registry.downloadedModelEntries()

        #expect(entries.map(\.model.name) == ["ggml-small", "ggml-base", "ggml-large-v3-turbo", "ggml-medium", "ggml-large-v3", "ggml-tiny"])
        #expect(entries[0].recommendation == .defaultRecommended)
        #expect(entries[0].model.checksum == "sha-ggml-small.bin")
        #expect(try registry.recommendedDefaultModel()?.name == "ggml-small")
    }

    @Test func ignoresManifestModelsThatAreNotDownloaded() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "ggml-small.bin"))
        try manifest(filename: "ggml-small.bin", status: "partial", sha256: nil)
            .write(to: root.appending(path: "ggml-small.bin.manifest.json"), atomically: true, encoding: .utf8)

        let registry = ModelRegistry(modelsDirectory: root)

        #expect(try registry.downloadedModels().isEmpty)
    }



    @Test func acceptsDownloadedUnverifiedScriptManifests() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "ggml-base.bin"))
        try manifest(filename: "ggml-base.bin", status: "downloaded_unverified", sha256: nil)
            .write(to: root.appending(path: "ggml-base.bin.manifest.json"), atomically: true, encoding: .utf8)

        let registry = ModelRegistry(modelsDirectory: root)

        #expect(try registry.downloadedModels().map(\.name) == ["ggml-base"])
    }

    @Test func buildsStableDownloadURLs() {
        #expect(WhisperModelSize.largeV3Turbo.filename == "ggml-large-v3-turbo.bin")
        #expect(WhisperModelDownloadMirror.official.downloadURL(for: .small).absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")
        #expect(WhisperModelDownloadMirror.hfMirror.downloadURL(for: .tiny).absoluteString == "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")
    }



    @Test func scansWritableAndBundledModelDirectories() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writable = root.appending(path: "Writable", directoryHint: .isDirectory)
        let bundled = root.appending(path: "Bundled", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: writable, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try Data().write(to: writable.appending(path: "ggml-base.bin"))
        try Data().write(to: bundled.appending(path: "ggml-tiny.bin"))

        let registry = ModelRegistry(modelsDirectory: writable, additionalModelsDirectories: [bundled])

        #expect(try registry.downloadedModels().map(\.name) == ["ggml-base", "ggml-tiny"])
    }

    @Test func validatesManualModelExtensions() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = root.appending(path: "ggml-large-v3.bin")
        let invalid = root.appending(path: "readme.md")
        try Data().write(to: valid)
        try Data().write(to: invalid)

        let registry = ModelRegistry(modelsDirectory: root)

        #expect(registry.validateManualModel(at: valid))
        #expect(!registry.validateManualModel(at: invalid))
    }
}


private func manifest(filename: String, status: String, sha256: String?) -> String {
    """
    {
      "filename": "\(filename)",
      "source_url": "https://example.invalid/\(filename)",
      "size_bytes": 123,
      "sha256": \(sha256.map { "\"\($0)\"" } ?? "null"),
      "status": "\(status)"
    }
    """
}
