import CryptoKit
import Foundation

public enum WhisperModelSize: String, CaseIterable, Codable, Identifiable, Sendable {
  case tiny
  case base
  case small
  case medium
  case largeV3 = "large-v3"
  case largeV3Turbo = "large-v3-turbo"

  public var id: String { rawValue }
  public var filename: String { "ggml-\(rawValue).bin" }
  public var displayName: String { rawValue }
}

public enum WhisperModelDownloadMirror: String, CaseIterable, Codable, Identifiable, Sendable {
  case official
  case hfMirror = "hf-mirror"

  public var id: String { rawValue }

  public var baseURL: URL {
    switch self {
    case .official:
      return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main")!
    case .hfMirror:
      return URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main")!
    }
  }

  public func downloadURL(for model: WhisperModelSize) -> URL {
    baseURL.appending(path: model.filename, directoryHint: .notDirectory)
  }
}

public enum WhisperModelDownloadError: LocalizedError, Sendable {
  case invalidHTTPStatus(Int)
  case missingHTTPResponse
  case missingDownloadedFile

  public var errorDescription: String? {
    switch self {
    case .invalidHTTPStatus(let status):
      return "Model download failed with HTTP status \(status)."
    case .missingHTTPResponse:
      return "Model download did not return an HTTP response."
    case .missingDownloadedFile:
      return "Downloaded model file was not found after transfer."
    }
  }
}

public struct WhisperModelDownloader: Sendable {
  public var modelsDirectory: URL

  public init(modelsDirectory: URL) {
    self.modelsDirectory = modelsDirectory
  }

  public func download(
    model: WhisperModelSize,
    mirror: WhisperModelDownloadMirror = .official
  ) async throws -> WhisperModelManifest {
    let sourceURL = mirror.downloadURL(for: model)
    let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw WhisperModelDownloadError.missingHTTPResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw WhisperModelDownloadError.invalidHTTPStatus(httpResponse.statusCode)
    }

    let fileManager = FileManager.default
    try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

    let destinationURL = modelsDirectory.appending(
      path: model.filename, directoryHint: .notDirectory)
    let partialURL = modelsDirectory.appending(
      path: "\(model.filename).part", directoryHint: .notDirectory)
    try? fileManager.removeItem(at: partialURL)
    try fileManager.moveItem(at: temporaryURL, to: partialURL)
    try? fileManager.removeItem(at: destinationURL)
    try fileManager.moveItem(at: partialURL, to: destinationURL)

    guard fileManager.fileExists(atPath: destinationURL.path) else {
      throw WhisperModelDownloadError.missingDownloadedFile
    }

    let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
    let sizeBytes = (attributes[.size] as? NSNumber)?.int64Value
    let sha256 = try sha256Hex(for: destinationURL)
    let manifest = WhisperModelManifest(
      filename: model.filename,
      path: destinationURL.path,
      sourceURL: sourceURL,
      sizeBytes: sizeBytes,
      sha256: sha256,
      status: "downloaded"
    )
    try writeManifest(manifest, for: model)
    return manifest
  }

  private func writeManifest(_ manifest: WhisperModelManifest, for model: WhisperModelSize) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    let manifestURL = modelsDirectory.appending(
      path: "\(model.filename).manifest.json",
      directoryHint: .notDirectory
    )
    try data.write(to: manifestURL, options: .atomic)
  }

  private func sha256Hex(for url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
