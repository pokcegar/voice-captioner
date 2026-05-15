import Foundation

public struct DownloadedWhisperModel: Equatable, Sendable {
    public var model: WhisperModel
    public var manifest: WhisperModelManifest?
    public var recommendation: WhisperModelRecommendation

    public init(
        model: WhisperModel,
        manifest: WhisperModelManifest? = nil,
        recommendation: WhisperModelRecommendation
    ) {
        self.model = model
        self.manifest = manifest
        self.recommendation = recommendation
    }
}

public struct WhisperModelManifest: Codable, Equatable, Sendable {
    public var filename: String
    public var path: String?
    public var sourceURL: URL?
    public var sizeBytes: Int64?
    public var sha256: String?
    public var status: String?

    public init(
        filename: String,
        path: String? = nil,
        sourceURL: URL? = nil,
        sizeBytes: Int64? = nil,
        sha256: String? = nil,
        status: String? = nil
    ) {
        self.filename = filename
        self.path = path
        self.sourceURL = sourceURL
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case filename
        case path
        case sourceURL = "source_url"
        case sizeBytes = "size_bytes"
        case sha256
        case status
    }
}

public enum WhisperModelRecommendation: Int, Codable, Equatable, Sendable, Comparable {
    case defaultRecommended = 0
    case quickPreview = 1
    case quality = 2
    case maximumQuality = 3
    case smokeOnly = 4
    case manualOrUnknown = 5

    public static func < (lhs: WhisperModelRecommendation, rhs: WhisperModelRecommendation) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ModelRegistry {
    public var modelsDirectory: URL
    public var additionalModelsDirectories: [URL]
    public var fileManager: FileManager

    public init(
        modelsDirectory: URL,
        additionalModelsDirectories: [URL] = [],
        fileManager: FileManager = .default
    ) {
        self.modelsDirectory = modelsDirectory
        self.additionalModelsDirectories = additionalModelsDirectories
        self.fileManager = fileManager
    }

    public func downloadedModels() throws -> [WhisperModel] {
        try downloadedModelEntries().map(\.model)
    }

    public func downloadedModelEntries() throws -> [DownloadedWhisperModel] {
        let entries = try allModelDirectories().flatMap { directory -> [DownloadedWhisperModel] in
            guard fileManager.fileExists(atPath: directory.path) else { return [] }
            let urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let manifests = try manifestsByFilename(in: urls)

            return urls
                .filter(isSupportedModelFile)
                .compactMap { url -> DownloadedWhisperModel? in
                    let manifest = manifests[url.lastPathComponent]
                    if let manifest, !Self.isUsableManifestStatus(manifest.status) {
                        return nil
                    }
                    guard fileManager.fileExists(atPath: url.path) else { return nil }
                    let name = url.deletingPathExtension().lastPathComponent
                    let model = WhisperModel(name: name, localPath: url, checksum: manifest?.sha256)
                    return DownloadedWhisperModel(
                        model: model,
                        manifest: manifest,
                        recommendation: recommendation(for: name)
                    )
                }
        }

        return entries
            .reduce(into: [String: DownloadedWhisperModel]()) { partial, entry in
                partial[entry.model.localPath.path] = entry
            }
            .values
            .sorted { lhs, rhs in
                if lhs.recommendation != rhs.recommendation {
                    return lhs.recommendation < rhs.recommendation
                }
                return lhs.model.name < rhs.model.name
            }
    }

    public func recommendedDefaultModel() throws -> WhisperModel? {
        try downloadedModelEntries().first?.model
    }

    public func validateManualModel(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path) && isSupportedModelFile(url)
    }

    private func allModelDirectories() -> [URL] {
        ([modelsDirectory] + additionalModelsDirectories).reduce(into: [URL]()) { partial, url in
            guard !partial.contains(where: { $0.path == url.path }) else { return }
            partial.append(url)
        }
    }

    private static func isUsableManifestStatus(_ status: String?) -> Bool {
        guard let status else { return true }
        return ["downloaded", "downloaded_unverified"].contains(status)
    }

    private func manifestsByFilename(in urls: [URL]) throws -> [String: WhisperModelManifest] {
        try urls
            .filter { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent.hasSuffix(".manifest.json") }
            .reduce(into: [String: WhisperModelManifest]()) { partial, url in
                let data = try Data(contentsOf: url)
                let manifest = try JSONDecoder().decode(WhisperModelManifest.self, from: data)
                partial[manifest.filename] = manifest
            }
    }

    private func isSupportedModelFile(_ url: URL) -> Bool {
        ["bin", "gguf"].contains(url.pathExtension.lowercased())
    }

    private func recommendation(for name: String) -> WhisperModelRecommendation {
        switch name.replacingOccurrences(of: "ggml-", with: "") {
        case "small":
            return .defaultRecommended
        case "base":
            return .quickPreview
        case "medium", "large-v3-turbo":
            return .quality
        case "large-v3":
            return .maximumQuality
        case "tiny":
            return .smokeOnly
        default:
            return .manualOrUnknown
        }
    }
}
