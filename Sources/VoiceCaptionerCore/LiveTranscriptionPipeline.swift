@preconcurrency import AVFoundation
import Foundation

public struct LiveTranscriptionUpdate: Equatable, Sendable {
    public var chunks: [AudioChunkWorkItem]
    public var draftSegments: [TranscriptSegment]

    public init(chunks: [AudioChunkWorkItem], draftSegments: [TranscriptSegment]) {
        self.chunks = chunks
        self.draftSegments = draftSegments
    }
}

open class LiveTranscriptionPipeline: @unchecked Sendable {
    private let transcriber: any TranscriptionProvider
    private let diarizer: any DiarizationProvider
    private let chunkExtractor: AudioChunkExtractor
    private let fileManager: FileManager
    private var chunksByID: [String: AudioChunkWorkItem] = [:]
    private var segmentsByChunkID: [String: [TranscriptSegment]] = [:]

    public init(
        transcriber: any TranscriptionProvider,
        diarizer: any DiarizationProvider = TrackAwareDiarizationProvider(),
        chunkExtractor: AudioChunkExtractor = AudioChunkExtractor(),
        fileManager: FileManager = .default
    ) {
        self.transcriber = transcriber
        self.diarizer = diarizer
        self.chunkExtractor = chunkExtractor
        self.fileManager = fileManager
    }

    open func poll(
        meeting: MeetingFolder,
        model: WhisperModel,
        chunkDuration: TimeInterval,
        trailingSafetyMargin: TimeInterval = 1.0
    ) async throws -> LiveTranscriptionUpdate {
        let candidates = try planAvailableChunks(
            meeting: meeting,
            chunkDuration: chunkDuration,
            trailingSafetyMargin: trailingSafetyMargin
        )
        for chunk in candidates where chunksByID[chunk.id]?.status != .complete && chunksByID[chunk.id]?.status != .transcribing {
            chunksByID[chunk.id] = chunk
            try await transcribe(chunk, meeting: meeting, model: model)
        }
        let chunks = chunksByID.values.sorted(by: sortChunks)
        let segments = TranscriptMerger.merge(chunks.compactMap { segmentsByChunkID[$0.id] })
        try AudioChunker.writeManifest(chunks, to: meeting.chunksDirectory.appending(path: "live-chunks.json"))
        try writeRollingSnapshot(segments, to: meeting.transcriptDirectory.appending(path: "rolling-live.jsonl"))
        return LiveTranscriptionUpdate(chunks: chunks, draftSegments: segments)
    }

    public func currentDraftSegments() -> [TranscriptSegment] {
        TranscriptMerger.merge(chunksByID.values.sorted(by: sortChunks).compactMap { segmentsByChunkID[$0.id] })
    }

    private func transcribe(_ chunk: AudioChunkWorkItem, meeting: MeetingFolder, model: WhisperModel) async throws {
        var working = chunk
        working.status = .transcribing
        chunksByID[working.id] = working
        do {
            try chunkExtractor.extract(working, meeting: meeting)
            let chunkRelativeSegments = try await transcriber.transcribe(chunk: working.audioChunk(in: meeting), model: model)
            let timelineSegments = chunkRelativeSegments.map { segment in
                var normalized = segment
                normalized.start = working.timelineStart + segment.start
                normalized.end = working.timelineStart + segment.end
                normalized.isDraft = true
                return normalized
            }
            let labeled = try await diarizer.label(segments: timelineSegments, tracks: [])
            working.status = .complete
            working.lastError = nil
            chunksByID[working.id] = working
            segmentsByChunkID[working.id] = labeled
        } catch {
            working.status = .failed
            working.retryCount += 1
            working.lastError = String(describing: error)
            chunksByID[working.id] = working
        }
    }

    private func planAvailableChunks(
        meeting: MeetingFolder,
        chunkDuration: TimeInterval,
        trailingSafetyMargin: TimeInterval
    ) throws -> [AudioChunkWorkItem] {
        let tracks = meeting.metadata.tracks.filter { $0.kind == .system || $0.kind == .microphone }
        let planned = tracks.flatMap { track -> [AudioChunkWorkItem] in
            guard let availableDuration = readableDuration(for: track, meeting: meeting) else { return [] }
            let stableDuration = max(0, availableDuration - trailingSafetyMargin)
            guard stableDuration >= max(0.5, min(chunkDuration, 1.0)) else { return [] }
            let timelineOffset = track.startOffset ?? 0
            var chunks: [AudioChunkWorkItem] = []
            var sourceStart: TimeInterval = 0
            var index = 0
            while sourceStart < stableDuration {
                let sourceEnd = min(sourceStart + chunkDuration, stableDuration)
                guard sourceEnd - sourceStart >= 0.5 else { break }
                let id = "live-\(track.kind.rawValue)-\(String(format: "%05d", index))"
                chunks.append(AudioChunkWorkItem(
                    id: id,
                    track: track.kind,
                    sourceRelativePath: track.relativePath,
                    chunkRelativePath: "chunks/\(id).wav",
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
        return planned.sorted(by: sortChunks)
    }

    private func readableDuration(for track: AudioTrack, meeting: MeetingFolder) -> TimeInterval? {
        let url = meeting.rootURL.appending(path: track.relativePath, directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let file = try AVAudioFile(forReading: url)
            let sampleRate = file.fileFormat.sampleRate
            return sampleRate > 0 ? Double(file.length) / sampleRate : nil
        } catch {
            return nil
        }
    }

    private func writeRollingSnapshot(_ segments: [TranscriptSegment], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try segments.map { try String(data: encoder.encode($0), encoding: .utf8) ?? "{}" }
            .joined(separator: "\n")
            .data(using: .utf8) ?? Data()
        try data.write(to: url, options: .atomic)
    }

    private func sortChunks(_ lhs: AudioChunkWorkItem, _ rhs: AudioChunkWorkItem) -> Bool {
        if lhs.timelineStart == rhs.timelineStart {
            return lhs.track.rawValue < rhs.track.rawValue
        }
        return lhs.timelineStart < rhs.timelineStart
    }
}
