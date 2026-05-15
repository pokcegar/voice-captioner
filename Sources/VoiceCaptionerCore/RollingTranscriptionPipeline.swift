import Foundation

public enum RollingTranscriptionPipelineError: Error, Equatable {
    case missingChunkSource(URL)
}

public struct RollingTranscriptionResult: Equatable, Sendable {
    public var chunks: [AudioChunkWorkItem]
    public var rollingSegments: [TranscriptSegment]
    public var finalSegments: [TranscriptSegment]

    public init(chunks: [AudioChunkWorkItem], rollingSegments: [TranscriptSegment], finalSegments: [TranscriptSegment]) {
        self.chunks = chunks
        self.rollingSegments = rollingSegments
        self.finalSegments = finalSegments
    }
}

public final class RollingTranscriptionPipeline: @unchecked Sendable {
    private let transcriber: any TranscriptionProvider
    private let diarizer: any DiarizationProvider
    private let chunkExtractor: AudioChunkExtractor

    public init(
        transcriber: any TranscriptionProvider,
        diarizer: any DiarizationProvider = TrackAwareDiarizationProvider(),
        chunkExtractor: AudioChunkExtractor = AudioChunkExtractor()
    ) {
        self.transcriber = transcriber
        self.diarizer = diarizer
        self.chunkExtractor = chunkExtractor
    }

    public func run(
        meeting: MeetingFolder,
        model: WhisperModel,
        chunkDuration: TimeInterval? = nil
    ) async throws -> RollingTranscriptionResult {
        var chunks = try AudioChunker.planChunks(for: meeting, chunkDuration: chunkDuration)
        try chunkExtractor.extract(&chunks, meeting: meeting)
        let manifestURL = meeting.chunksDirectory.appending(path: "chunks.json", directoryHint: .notDirectory)
        try AudioChunker.writeManifest(chunks, to: manifestURL)

        var segmentGroups: [[TranscriptSegment]] = []
        for index in chunks.indices where chunks[index].status != .failed {
            chunks[index].status = .transcribing
            do {
                let chunk = chunks[index].audioChunk(in: meeting)
                let chunkRelativeSegments = try await transcriber.transcribe(chunk: chunk, model: model)
                let timelineSegments = normalizeToTimeline(chunkRelativeSegments, using: chunks[index])
                let labeled = try await diarizer.label(segments: timelineSegments, tracks: meeting.metadata.tracks)
                chunks[index].status = .complete
                segmentGroups.append(labeled)
                try appendJSONL(labeled, to: meeting.transcriptDirectory.appending(path: "rolling.jsonl", directoryHint: .notDirectory))
            } catch {
                chunks[index].status = .failed
                chunks[index].retryCount += 1
                chunks[index].lastError = String(describing: error)
            }
        }

        let rolling = TranscriptMerger.merge(segmentGroups)
        let final = rolling.map { segment in
            var finalSegment = segment
            finalSegment.isDraft = false
            return finalSegment
        }
        try writeFinalExports(meeting: meeting, segments: final)
        try AudioChunker.writeManifest(chunks, to: manifestURL)
        return RollingTranscriptionResult(chunks: chunks, rollingSegments: rolling, finalSegments: final)
    }

    private func normalizeToTimeline(_ segments: [TranscriptSegment], using chunk: AudioChunkWorkItem) -> [TranscriptSegment] {
        segments.map { segment in
            var normalized = segment
            normalized.start = chunk.timelineStart + segment.start
            normalized.end = chunk.timelineStart + segment.end
            return normalized
        }
    }

    private func appendJSONL(_ segments: [TranscriptSegment], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let handle: FileHandle
        if FileManager.default.fileExists(atPath: url.path) {
            handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
        }
        defer { try? handle.close() }
        for segment in segments {
            let data = try encoder.encode(segment)
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
        }
    }

    private func writeFinalExports(meeting: MeetingFolder, segments: [TranscriptSegment]) throws {
        let transcriptDirectory = meeting.transcriptDirectory
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
        try TranscriptExporter.markdown(meeting: meeting.metadata, segments: segments)
            .write(to: transcriptDirectory.appending(path: "final.md"), atomically: true, encoding: .utf8)
        try TranscriptExporter.srt(segments: segments)
            .write(to: transcriptDirectory.appending(path: "final.srt"), atomically: true, encoding: .utf8)
        try TranscriptExporter.json(segments: segments)
            .write(to: transcriptDirectory.appending(path: "final.json"), options: .atomic)
    }
}
