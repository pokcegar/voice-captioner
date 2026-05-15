import AVFoundation
import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("AudioChunkExtractor")
struct AudioChunkExtractorTests {
    @Test func extractsSourceLocalRangeToWhisperCompatibleWAV() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var meeting = try MeetingStore().createMeeting(outputRoot: root, title: "Extractor", now: Date(timeIntervalSince1970: 0))
        let sourceURL = meeting.audioDirectory.appending(path: "microphone.wav")
        try writeFixtureWave(to: sourceURL, duration: 3, sampleRate: 44_100, channels: 2)
        meeting.metadata.tracks = [
            AudioTrack(
                id: "microphone",
                kind: .microphone,
                relativePath: "audio/microphone.wav",
                startOffset: 7.5,
                timingConfidence: .observed,
                duration: 3
            )
        ]
        var chunks = try AudioChunker.planChunks(for: meeting, chunkDuration: 1)
        let target = try #require(chunks.first { $0.id == "microphone-00001" })
        #expect(target.sourceStart == 1)
        #expect(target.sourceEnd == 2)
        #expect(target.timelineStart == 8.5)
        #expect(target.timelineEnd == 9.5)

        try AudioChunkExtractor().extract(&chunks, meeting: meeting)

        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        let outputURL = meeting.rootURL.appending(path: target.chunkRelativePath)
        let output = try AVAudioFile(forReading: outputURL)
        #expect(output.processingFormat.sampleRate == 16_000)
        #expect(output.processingFormat.channelCount == 1)
        let outputDuration = Double(output.length) / output.processingFormat.sampleRate
        #expect(abs(outputDuration - 1.0) < 0.02)
        #expect(chunks.allSatisfy { $0.status == .pending })
    }

    @Test func recordsExtractionFailureOnChunkManifestItem() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var meeting = try MeetingStore().createMeeting(outputRoot: root, title: "Extractor", now: Date(timeIntervalSince1970: 0))
        meeting.metadata.tracks = [
            AudioTrack(id: "system", kind: .system, relativePath: "audio/missing.wav", startOffset: 0, duration: 1)
        ]
        var chunks = try AudioChunker.planChunks(for: meeting, chunkDuration: 1)

        try AudioChunkExtractor().extract(&chunks, meeting: meeting)

        #expect(chunks.count == 1)
        #expect(chunks[0].status == .failed)
        #expect(chunks[0].retryCount == 1)
        #expect(chunks[0].lastError?.contains("missing") == true || chunks[0].lastError?.contains("Missing") == true)
    }
}

private func writeFixtureWave(
    to url: URL,
    duration: TimeInterval,
    sampleRate: Double,
    channels: AVAudioChannelCount
) throws {
    let frameCount = AVAudioFrameCount(duration * sampleRate)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    for channel in 0..<Int(channels) {
        let samples = buffer.floatChannelData![channel]
        for frame in 0..<Int(frameCount) {
            samples[frame] = Float(sin(2.0 * Double.pi * 220.0 * Double(frame) / sampleRate) * 0.2)
        }
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}
