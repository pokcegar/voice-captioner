import Foundation

public struct WhisperProcessConfiguration: Equatable, Sendable {
    public var executableURL: URL
    public var timeoutSeconds: TimeInterval

    public init(executableURL: URL, timeoutSeconds: TimeInterval = 120) {
        self.executableURL = executableURL
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum WhisperProcessError: Error, Equatable {
    case executableMissing(URL)
    case modelMissing(URL)
    case chunkMissing(URL)
    case failed(exitCode: Int32, stderr: String)
}

public final class WhisperProcessTranscriber: TranscriptionProvider, @unchecked Sendable {
    private let configuration: WhisperProcessConfiguration

    public init(configuration: WhisperProcessConfiguration) {
        self.configuration = configuration
    }

    public func transcribe(chunk: AudioChunk, model: WhisperModel) async throws -> [TranscriptSegment] {
        guard FileManager.default.isExecutableFile(atPath: configuration.executableURL.path) else {
            throw WhisperProcessError.executableMissing(configuration.executableURL)
        }
        guard FileManager.default.fileExists(atPath: model.localPath.path) else {
            throw WhisperProcessError.modelMissing(model.localPath)
        }
        guard FileManager.default.fileExists(atPath: chunk.url.path) else {
            throw WhisperProcessError.chunkMissing(chunk.url)
        }

        let outputPrefix = chunk.url.deletingPathExtension().appending(path: "whisper-output", directoryHint: .notDirectory)
        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = [
            "-m", model.localPath.path,
            "-f", chunk.url.path,
            "-oj",
            "-of", outputPrefix.path
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw WhisperProcessError.failed(exitCode: process.terminationStatus, stderr: stderr)
        }

        let jsonURL = outputPrefix.appendingPathExtension("json")
        return try WhisperJSONParser.parse(url: jsonURL, track: chunk.track)
    }
}

public enum WhisperJSONParser {
    public static func parse(url: URL, track: AudioTrackKind) throws -> [TranscriptSegment] {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(WhisperOutput.self, from: data)
        return decoded.transcription.compactMap { item in
            guard let start = item.timestamps.from, let end = item.timestamps.to else { return nil }
            return TranscriptSegment(
                id: UUID().uuidString,
                sourceTrack: track,
                speakerLabel: track == .system ? "Remote" : "Local",
                start: start,
                end: end,
                text: item.text.trimmingCharacters(in: .whitespacesAndNewlines),
                isDraft: true
            )
        }
    }

    private struct WhisperOutput: Decodable {
        var transcription: [TranscriptionItem]
    }

    private struct TranscriptionItem: Decodable {
        var timestamps: Timestamps
        var text: String
    }

    private struct Timestamps: Decodable {
        var from: TimeInterval?
        var to: TimeInterval?
    }
}
