import Foundation
import VoiceCaptionerCore

private struct DualCaptureSmokeReport: Codable {
    var startedAt: Date
    var stoppedAt: Date
    var system: AudioRecordingMetadata
    var microphone: AudioRecordingMetadata
    var startOffsetSeconds: TimeInterval?
    var estimatedDriftSeconds: TimeInterval?
    var driftToleranceSeconds: TimeInterval?
    var driftBasis: String
}

@main
struct DualCaptureSmoke {
    static func main() async {
        let root = URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: ".tmp/capture-smoke", directoryHint: .isDirectory)
        let systemURL = root.appending(path: "dual-system.wav")
        let microphoneURL = root.appending(path: "dual-microphone.wav")
        let metadataURL = root.appending(path: "dual-metadata.json")
        let system = SystemAudioRecorder()
        let microphone = MicrophoneRecorder()

        do {
            let start = Date()
            try await system.start(outputURL: systemURL)
            try microphone.start(outputURL: microphoneURL)
            try await Task.sleep(for: .seconds(3))
            async let stoppedSystem = system.stopWithMetadata()
            async let stoppedMicrophone = microphone.stopWithMetadata()
            let (systemResult, microphoneResult) = try await (stoppedSystem, stoppedMicrophone)
            let systemSize = try fileSize(systemResult.file)
            let microphoneSize = try fileSize(microphoneResult.file)
            let stoppedAt = Date()
            let startOffset = startOffsetSeconds(system: systemResult.metadata, microphone: microphoneResult.metadata)
            let drift = durationDriftSeconds(system: systemResult.metadata, microphone: microphoneResult.metadata)
            let report = DualCaptureSmokeReport(
                startedAt: start,
                stoppedAt: stoppedAt,
                system: systemResult.metadata,
                microphone: microphoneResult.metadata,
                startOffsetSeconds: startOffset,
                estimatedDriftSeconds: drift,
                driftToleranceSeconds: drift.map { max($0 + 0.05, 0.10) },
                driftBasis: "absolute difference between inspected WAV durations; start offset uses first observed/inferred sample wall-clock timestamps"
            )
            try writeReport(report, to: metadataURL)
            print("started_at=\(ISO8601DateFormatter().string(from: start))")
            print("system=\(systemResult.file.path)")
            print("system_bytes=\(systemSize)")
            print("system_sample_rate=\(systemResult.metadata.sampleRate ?? 0)")
            print("system_channel_count=\(systemResult.metadata.channelCount ?? 0)")
            print("system_duration_seconds=\(systemResult.metadata.duration ?? 0)")
            print("system_first_sample_time=\(systemResult.metadata.firstSamplePresentationTime ?? 0)")
            print("system_timing_confidence=\(systemResult.metadata.timingConfidence.rawValue)")
            print("microphone=\(microphoneResult.file.path)")
            print("microphone_bytes=\(microphoneSize)")
            print("microphone_sample_rate=\(microphoneResult.metadata.sampleRate ?? 0)")
            print("microphone_channel_count=\(microphoneResult.metadata.channelCount ?? 0)")
            print("microphone_duration_seconds=\(microphoneResult.metadata.duration ?? 0)")
            print("microphone_timing_confidence=\(microphoneResult.metadata.timingConfidence.rawValue)")
            if let startOffset {
                print("start_offset_seconds=\(startOffset)")
            }
            if let drift {
                print("estimated_drift_seconds=\(drift)")
            }
            print("metadata=\(metadataURL.path)")
        } catch {
            fputs("dual-capture-smoke failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func fileSize(_ url: URL) throws -> Int {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.intValue ?? 0
    }

    private static func startOffsetSeconds(
        system: AudioRecordingMetadata,
        microphone: AudioRecordingMetadata
    ) -> TimeInterval? {
        guard let systemStart = system.firstSampleObservedAt,
              let microphoneStart = microphone.firstSampleObservedAt
        else {
            return nil
        }
        return systemStart.timeIntervalSince(microphoneStart)
    }

    private static func durationDriftSeconds(
        system: AudioRecordingMetadata,
        microphone: AudioRecordingMetadata
    ) -> TimeInterval? {
        guard let systemDuration = system.duration,
              let microphoneDuration = microphone.duration
        else {
            return nil
        }
        return abs(systemDuration - microphoneDuration)
    }

    private static func writeReport(_ report: DualCaptureSmokeReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
