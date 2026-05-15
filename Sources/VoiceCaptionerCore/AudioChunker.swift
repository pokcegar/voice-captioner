import Foundation

public enum AudioChunkStatus: String, Codable, Equatable, Sendable {
    case pending
    case transcribing
    case complete
    case failed
}

public struct AudioChunkWorkItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var track: AudioTrackKind
    public var sourceRelativePath: String
    public var chunkRelativePath: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var status: AudioChunkStatus
    public var retryCount: Int
    public var lastError: String?

    public init(
        id: String,
        track: AudioTrackKind,
        sourceRelativePath: String,
        chunkRelativePath: String,
        start: TimeInterval,
        end: TimeInterval,
        status: AudioChunkStatus = .pending,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.track = track
        self.sourceRelativePath = sourceRelativePath
        self.chunkRelativePath = chunkRelativePath
        self.start = start
        self.end = end
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
    }

    public func audioChunk(in meeting: MeetingFolder) -> AudioChunk {
        AudioChunk(
            track: track,
            url: meeting.rootURL.appending(path: chunkRelativePath, directoryHint: .notDirectory),
            start: start,
            end: end
        )
    }
}

public enum AudioChunkerError: Error, Equatable {
    case missingDuration(AudioTrackKind)
    case nonPositiveDuration(AudioTrackKind)
}

public enum AudioChunker {
    public static func planChunks(
        for meeting: MeetingFolder,
        chunkDuration: TimeInterval? = nil
    ) throws -> [AudioChunkWorkItem] {
        let duration = chunkDuration ?? meeting.metadata.transcriptionDelaySeconds
        let sourceTracks = meeting.metadata.tracks.filter { $0.kind == .system || $0.kind == .microphone }
        return try sourceTracks.flatMap { track in
            try planChunks(for: track, chunkDuration: duration)
        }
        .sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.track.rawValue < rhs.track.rawValue
            }
            return lhs.start < rhs.start
        }
    }

    public static func writeManifest(_ chunks: [AudioChunkWorkItem], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(chunks)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func planChunks(for track: AudioTrack, chunkDuration: TimeInterval) throws -> [AudioChunkWorkItem] {
        guard let duration = track.duration else { throw AudioChunkerError.missingDuration(track.kind) }
        guard duration > 0, chunkDuration > 0 else { throw AudioChunkerError.nonPositiveDuration(track.kind) }

        var chunks: [AudioChunkWorkItem] = []
        var start: TimeInterval = 0
        var index = 0
        while start < duration {
            let end = min(start + chunkDuration, duration)
            let id = "\(track.kind.rawValue)-\(String(format: "%05d", index))"
            let chunkRelativePath = "chunks/\(track.kind.rawValue)-\(String(format: "%05d", index)).wav"
            chunks.append(AudioChunkWorkItem(
                id: id,
                track: track.kind,
                sourceRelativePath: track.relativePath,
                chunkRelativePath: chunkRelativePath,
                start: start + (track.startOffset ?? 0),
                end: end + (track.startOffset ?? 0)
            ))
            start = end
            index += 1
        }
        return chunks
    }
}
