import Foundation

public struct ModelRegistry {
    public var modelsDirectory: URL
    public var fileManager: FileManager

    public init(modelsDirectory: URL, fileManager: FileManager = .default) {
        self.modelsDirectory = modelsDirectory
        self.fileManager = fileManager
    }

    public func downloadedModels() throws -> [WhisperModel] {
        guard fileManager.fileExists(atPath: modelsDirectory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { ["bin", "gguf"].contains($0.pathExtension.lowercased()) }
            .map { WhisperModel(name: $0.deletingPathExtension().lastPathComponent, localPath: $0) }
            .sorted { $0.name < $1.name }
    }

    public func validateManualModel(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
            && ["bin", "gguf"].contains(url.pathExtension.lowercased())
    }
}
