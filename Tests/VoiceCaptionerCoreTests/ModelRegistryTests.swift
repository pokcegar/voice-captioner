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
