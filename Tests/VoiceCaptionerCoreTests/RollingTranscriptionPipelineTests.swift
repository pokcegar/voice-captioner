import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("RollingTranscriptionPipeline")
struct RollingTranscriptionPipelineTests {
    @Test func plansChunksByTrackDurationAndOffset() throws {
        let meeting = meetingWithTracks(systemDuration: 65, microphoneDuration: 31, microphoneOffset: 0.1)

        let chunks = try AudioChunker.planChunks(for: meeting, chunkDuration: 30)

        #expect(chunks.map(\.id) == ["system-00000", "microphone-00000", "system-00001", "microphone-00001", "system-00002"])
        #expect(chunks.first { $0.id == "microphone-00000" }?.start == 0.1)
        #expect(chunks.first { $0.id == "system-00002" }?.end == 65)
    }

    @Test func writesRollingJsonlFinalExportsAndChunkManifest() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var meeting = try MeetingStore().createMeeting(outputRoot: root, title: "Pipeline", now: Date(timeIntervalSince1970: 0))
        let systemURL = meeting.audioDirectory.appending(path: "system.wav")
        let microphoneURL = meeting.audioDirectory.appending(path: "microphone.wav")
        try Data("system".utf8).write(to: systemURL)
        try Data("microphone".utf8).write(to: microphoneURL)
        meeting.metadata.tracks = [
            AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0, timingConfidence: .observed, duration: 2),
            AudioTrack(id: "microphone", kind: .microphone, relativePath: "audio/microphone.wav", startOffset: 0.05, timingConfidence: .observed, duration: 2)
        ]
        let pipeline = RollingTranscriptionPipeline(transcriber: FakeTranscriber())
        let model = WhisperModel(name: "fake", localPath: root.appending(path: "fake.bin"))

        let result = try await pipeline.run(meeting: meeting, model: model, chunkDuration: 30)

        #expect(result.chunks.allSatisfy { $0.status == .complete })
        #expect(result.rollingSegments.count == 2)
        #expect(result.finalSegments.allSatisfy { !$0.isDraft })
        #expect(FileManager.default.fileExists(atPath: meeting.chunksDirectory.appending(path: "chunks.json").path))
        #expect(FileManager.default.fileExists(atPath: meeting.transcriptDirectory.appending(path: "rolling.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: meeting.transcriptDirectory.appending(path: "final.md").path))
        #expect(FileManager.default.fileExists(atPath: meeting.transcriptDirectory.appending(path: "final.srt").path))
        #expect(FileManager.default.fileExists(atPath: meeting.transcriptDirectory.appending(path: "final.json").path))
    }
}

private func meetingWithTracks(systemDuration: TimeInterval, microphoneDuration: TimeInterval, microphoneOffset: TimeInterval) -> MeetingFolder {
    let root = URL(filePath: "/tmp/meeting")
    let metadata = MeetingMetadata(
        id: "meeting",
        title: "Meeting",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        status: .complete,
        transcriptionDelaySeconds: 30,
        tracks: [
            AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0, timingConfidence: .observed, duration: systemDuration),
            AudioTrack(id: "microphone", kind: .microphone, relativePath: "audio/microphone.wav", startOffset: microphoneOffset, timingConfidence: .observed, duration: microphoneDuration)
        ]
    )
    return MeetingFolder(rootURL: root, metadata: metadata)
}

private struct FakeTranscriber: TranscriptionProvider {
    func transcribe(chunk: AudioChunk, model: WhisperModel) async throws -> [TranscriptSegment] {
        [TranscriptSegment(
            id: "\(chunk.track.rawValue)-\(Int(chunk.start * 1000))",
            sourceTrack: chunk.track,
            speakerLabel: "",
            start: chunk.start,
            end: chunk.end,
            text: "\(chunk.track.rawValue) text",
            isDraft: true
        )]
    }
}
