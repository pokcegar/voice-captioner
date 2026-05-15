import AVFoundation
import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("LiveTranscriptionPipeline")
struct LiveTranscriptionPipelineTests {
    @Test func pollsStableAudioChunksIntoDraftSegments() async throws {
        let root = try temporaryLiveTranscriptionDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meeting = try MeetingStore().createMeeting(outputRoot: root, title: "Live")
        try FileManager.default.createDirectory(at: meeting.audioDirectory, withIntermediateDirectories: true)
        let systemURL = meeting.audioDirectory.appending(path: "system.wav")
        try writeSilentWAV(to: systemURL, duration: 3)
        var metadata = meeting.metadata
        metadata.status = .recording
        metadata.tracks = [
            AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0, timingConfidence: .observed)
        ]
        try MeetingStore().writeMetadata(metadata, to: meeting.metadataURL)
        let liveMeeting = MeetingFolder(rootURL: meeting.rootURL, metadata: metadata)
        let transcriber = FakeLiveTranscriber()
        let pipeline = LiveTranscriptionPipeline(transcriber: transcriber)
        let model = WhisperModel(name: "fake", localPath: systemURL)

        let update = try await pipeline.poll(meeting: liveMeeting, model: model, chunkDuration: 1, trailingSafetyMargin: 0)

        #expect(update.chunks.count == 3)
        #expect(update.chunks.allSatisfy { $0.status == .complete })
        #expect(update.draftSegments.count == 3)
        #expect(update.draftSegments.allSatisfy { $0.isDraft })
        #expect(update.draftSegments.map(\.text) == ["draft-system-0", "draft-system-1", "draft-system-2"])
        #expect(FileManager.default.fileExists(atPath: liveMeeting.chunksDirectory.appending(path: "live-chunks.json").path))
        #expect(FileManager.default.fileExists(atPath: liveMeeting.transcriptDirectory.appending(path: "rolling-live.jsonl").path))
        #expect(await transcriber.runCount() == 3)

        let second = try await pipeline.poll(meeting: liveMeeting, model: model, chunkDuration: 1, trailingSafetyMargin: 0)
        #expect(second.draftSegments.count == 3)
        #expect(await transcriber.runCount() == 3)
    }
}

private actor FakeLiveTranscriber: TranscriptionProvider {
    private var runs = 0

    func runCount() -> Int { runs }

    func transcribe(chunk: AudioChunk, model: WhisperModel) async throws -> [TranscriptSegment] {
        runs += 1
        return [TranscriptSegment(
            id: "draft-\(chunk.track.rawValue)-\(Int(chunk.sourceStart))",
            sourceTrack: chunk.track,
            speakerLabel: "",
            start: 0,
            end: min(1, chunk.sourceEnd - chunk.sourceStart),
            text: "draft-\(chunk.track.rawValue)-\(Int(chunk.sourceStart))",
            isDraft: true
        )]
    }
}

private func writeSilentWAV(to url: URL, duration: TimeInterval) throws {
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else {
        throw NSError(domain: "LiveTranscriptionPipelineTests", code: 1)
    }
    let frames = AVAudioFrameCount(duration * format.sampleRate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
        throw NSError(domain: "LiveTranscriptionPipelineTests", code: 2)
    }
    buffer.frameLength = frames
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

private func temporaryLiveTranscriptionDirectory() throws -> URL {
    let projectRoot = URL(filePath: FileManager.default.currentDirectoryPath)
    let url = projectRoot
        .appending(path: ".tmp/tests/live-transcription-pipeline-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
