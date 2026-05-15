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
    /// Offset inside the source WAV. Only the chunk extractor should use source times.
    public var sourceStart: TimeInterval
    /// Offset inside the source WAV. Only the chunk extractor should use source times.
    public var sourceEnd: TimeInterval
    /// Meeting timeline offset after applying the capture track's startOffset.
    public var timelineStart: TimeInterval
    /// Meeting timeline offset after applying the capture track's startOffset.
    public var timelineEnd: TimeInterval
    public var status: AudioChunkStatus
    public var retryCount: Int
    public var lastError: String?

    public init(
        id: String,
        track: AudioTrackKind,
        sourceRelativePath: String,
        chunkRelativePath: String,
        sourceStart: TimeInterval,
        sourceEnd: TimeInterval,
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval,
        status: AudioChunkStatus = .pending,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.track = track
        self.sourceRelativePath = sourceRelativePath
        self.chunkRelativePath = chunkRelativePath
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.timelineStart = timelineStart
        self.timelineEnd = timelineEnd
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
    }

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
        self.init(
            id: id,
            track: track,
            sourceRelativePath: sourceRelativePath,
            chunkRelativePath: chunkRelativePath,
            sourceStart: start,
            sourceEnd: end,
            timelineStart: start,
            timelineEnd: end,
            status: status,
            retryCount: retryCount,
            lastError: lastError
        )
    }

    @available(*, deprecated, message: "Use sourceStart/timelineStart to avoid mixing extractor and transcript time domains.")
    public var start: TimeInterval {
        get { timelineStart }
        set {
            timelineStart = newValue
            sourceStart = newValue
        }
    }

    @available(*, deprecated, message: "Use sourceEnd/timelineEnd to avoid mixing extractor and transcript time domains.")
    public var end: TimeInterval {
        get { timelineEnd }
        set {
            timelineEnd = newValue
            sourceEnd = newValue
        }
    }

    public var timelineOffset: TimeInterval { timelineStart - sourceStart }

    public func audioChunk(in meeting: MeetingFolder) -> AudioChunk {
        AudioChunk(
            track: track,
            url: meeting.rootURL.appending(path: chunkRelativePath, directoryHint: .notDirectory),
            sourceStart: sourceStart,
            sourceEnd: sourceEnd,
            timelineStart: timelineStart,
            timelineEnd: timelineEnd
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
            if lhs.timelineStart == rhs.timelineStart {
                return lhs.track.rawValue < rhs.track.rawValue
            }
            return lhs.timelineStart < rhs.timelineStart
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

        let timelineOffset = track.startOffset ?? 0
        var chunks: [AudioChunkWorkItem] = []
        var sourceStart: TimeInterval = 0
        var index = 0
        while sourceStart < duration {
            let sourceEnd = min(sourceStart + chunkDuration, duration)
            let id = "\(track.kind.rawValue)-\(String(format: "%05d", index))"
            let chunkRelativePath = "chunks/\(track.kind.rawValue)-\(String(format: "%05d", index)).wav"
            chunks.append(AudioChunkWorkItem(
                id: id,
                track: track.kind,
                sourceRelativePath: track.relativePath,
                chunkRelativePath: chunkRelativePath,
                sourceStart: sourceStart,
                sourceEnd: sourceEnd,
                timelineStart: sourceStart + timelineOffset,
                timelineEnd: sourceEnd + timelineOffset
            ))
            sourceStart = sourceEnd
            index += 1
        }
        return chunks
    }
}
