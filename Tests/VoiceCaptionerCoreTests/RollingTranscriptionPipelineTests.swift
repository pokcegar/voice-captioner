import AVFoundation
import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("RollingTranscriptionPipeline")
struct RollingTranscriptionPipelineTests {
    @Test func plansChunksByTrackDurationAndOffset() throws {
        let meeting = meetingWithTracks(systemDuration: 65, microphoneDuration: 31, microphoneOffset: 0.1)

        let chunks = try AudioChunker.planChunks(for: meeting, chunkDuration: 30)

        #expect(chunks.map(\.id) == ["system-00000", "microphone-00000", "system-00001", "microphone-00001", "system-00002"])
        let firstMicrophone = try #require(chunks.first { $0.id == "microphone-00000" })
        #expect(firstMicrophone.sourceStart == 0)
        #expect(firstMicrophone.sourceEnd == 30)
        #expect(firstMicrophone.timelineStart == 0.1)
        #expect(firstMicrophone.timelineEnd == 30.1)
        #expect(chunks.first { $0.id == "system-00002" }?.sourceEnd == 65)
        #expect(chunks.first { $0.id == "system-00002" }?.timelineEnd == 65)
    }

    @Test func writesRollingJsonlFinalExportsAndChunkManifest() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var meeting = try MeetingStore().createMeeting(outputRoot: root, title: "Pipeline", now: Date(timeIntervalSince1970: 0))
        let systemURL = meeting.audioDirectory.appending(path: "system.wav")
        let microphoneURL = meeting.audioDirectory.appending(path: "microphone.wav")
        try writeSineWave(to: systemURL, duration: 2, frequency: 440)
        try writeSineWave(to: microphoneURL, duration: 2, frequency: 660)
        meeting.metadata.tracks = [
            AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0, timingConfidence: .observed, duration: 2),
            AudioTrack(id: "microphone", kind: .microphone, relativePath: "audio/microphone.wav", startOffset: 0.05, timingConfidence: .observed, duration: 2)
        ]
        let pipeline = RollingTranscriptionPipeline(transcriber: FakeTranscriber())
        let model = WhisperModel(name: "fake", localPath: root.appending(path: "fake.bin"))

        let result = try await pipeline.run(meeting: meeting, model: model, chunkDuration: 30)

        #expect(result.chunks.allSatisfy { $0.status == .complete })
        #expect(result.rollingSegments.count == 2)
        #expect(result.rollingSegments.first { $0.sourceTrack == .microphone }?.start == 0.05)
        #expect(result.rollingSegments.first { $0.sourceTrack == .microphone }?.end == 2.05)
        #expect(result.finalSegments.allSatisfy { !$0.isDraft })
        #expect(FileManager.default.fileExists(atPath: meeting.chunksDirectory.appending(path: "chunks.json").path))
        #expect(FileManager.default.fileExists(atPath: meeting.transcriptDirectory.appending(path: "rolling.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: meeting.transcriptDirectory.appending(path: "final.md").path))
        #expect(FileManager.default.fileExists(atPath: meeting.transcriptDirectory.appending(path: "final.srt").path))
        #expect(FileManager.default.fileExists(atPath: meeting.transcriptDirectory.appending(path: "final.json").path))
    }

    @Test func fakePipelineSmokePreservesMultiChunkTimelineOffsets() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var meeting = try MeetingStore().createMeeting(outputRoot: root, title: "Offset Pipeline", now: Date(timeIntervalSince1970: 0))
        let systemURL = meeting.audioDirectory.appending(path: "system.wav")
        let microphoneURL = meeting.audioDirectory.appending(path: "microphone.wav")
        try writeSineWave(to: systemURL, duration: 4, frequency: 440)
        try writeSineWave(to: microphoneURL, duration: 4, frequency: 660)
        meeting.metadata.tracks = [
            AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0, timingConfidence: .observed, duration: 4),
            AudioTrack(id: "microphone", kind: .microphone, relativePath: "audio/microphone.wav", startOffset: 1.25, timingConfidence: .observed, duration: 4)
        ]
        let pipeline = RollingTranscriptionPipeline(transcriber: FakeTranscriber())
        let model = WhisperModel(name: "fake", localPath: root.appending(path: "fake.bin"))

        let result = try await pipeline.run(meeting: meeting, model: model, chunkDuration: 2)

        #expect(result.chunks.map(\.id) == ["system-00000", "microphone-00000", "system-00001", "microphone-00001"])
        let secondMicrophone = try #require(result.chunks.first { $0.id == "microphone-00001" })
        #expect(secondMicrophone.sourceStart == 2)
        #expect(secondMicrophone.sourceEnd == 4)
        #expect(secondMicrophone.timelineStart == 3.25)
        #expect(secondMicrophone.timelineEnd == 5.25)
        #expect(result.finalSegments.map(\.start) == [0, 1.25, 2, 3.25])
        #expect(result.finalSegments.map(\.end) == [2, 3.25, 4, 5.25])
        #expect(result.finalSegments.map(\.sourceTrack) == [.system, .microphone, .system, .microphone])

        let finalSRT = try String(contentsOf: meeting.transcriptDirectory.appending(path: "final.srt"), encoding: .utf8)
        #expect(finalSRT.contains("00:00:03,250 --> 00:00:05,250"))
        let manifest = try String(contentsOf: meeting.chunksDirectory.appending(path: "chunks.json"), encoding: .utf8)
        #expect(manifest.contains("\"sourceStart\" : 2"))
        #expect(manifest.contains("\"timelineStart\" : 3.25"))
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
            id: "\(chunk.track.rawValue)-\(Int(chunk.timelineStart * 1000))",
            sourceTrack: chunk.track,
            speakerLabel: "",
            start: 0,
            end: chunk.sourceEnd - chunk.sourceStart,
            text: "\(chunk.track.rawValue) text",
            isDraft: true
        )]
    }
}


private func writeSineWave(to url: URL, duration: TimeInterval, frequency: Double) throws {
    #if canImport(AVFoundation)
    let sampleRate = 44_100.0
    let frameCount = AVAudioFrameCount(duration * sampleRate)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    for channel in 0..<Int(format.channelCount) {
        let samples = buffer.floatChannelData![channel]
        for frame in 0..<Int(frameCount) {
            samples[frame] = Float(sin(2.0 * Double.pi * frequency * Double(frame) / sampleRate) * 0.2)
        }
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    #else
    throw NSError(domain: "AudioFixture", code: 1)
    #endif
}
