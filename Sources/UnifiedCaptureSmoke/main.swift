import AVFoundation
import Foundation
import VoiceCaptionerCore

private struct UnifiedCaptureSmokeReport: Codable {
    var startedAt: Date
    var stoppedAt: Date
    var requestedDurationSeconds: TimeInterval
    var actualElapsedSeconds: TimeInterval
    var system: AudioRecordingMetadata
    var microphone: AudioRecordingMetadata
    var assessment: CaptureGateAssessment
}

@main
struct UnifiedCaptureSmoke {
    static func main() async {
        let requestedDuration = requestedDurationSeconds()
        let root = URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: ".tmp/capture-smoke", directoryHint: .isDirectory)
        let systemURL = root.appending(path: "unified-system.wav")
        let microphoneURL = root.appending(path: "unified-microphone.wav")
        let metadataURL = root.appending(path: "unified-metadata.json")
        let recorder = UnifiedScreenCaptureAudioRecorder()

        do {
            try await ensureMicrophonePermission()
            let start = Date()
            try await recorder.start(systemURL: systemURL, microphoneURL: microphoneURL)
            try await Task.sleep(for: .seconds(requestedDuration))
            let result = try await recorder.stopWithMetadata()
            let systemSize = try fileSize(result.system.file)
            let microphoneSize = try fileSize(result.microphone.file)
            let stoppedAt = Date()
            let assessment = CaptureGateAssessment.evaluate(
                systemSize: systemSize,
                microphoneSize: microphoneSize,
                system: result.system.metadata,
                microphone: result.microphone.metadata
            )
            let report = UnifiedCaptureSmokeReport(
                startedAt: start,
                stoppedAt: stoppedAt,
                requestedDurationSeconds: requestedDuration,
                actualElapsedSeconds: stoppedAt.timeIntervalSince(start),
                system: result.system.metadata,
                microphone: result.microphone.metadata,
                assessment: assessment
            )
            try writeReport(report, to: metadataURL)

            print("started_at=\(ISO8601DateFormatter().string(from: start))")
            print("requested_duration_seconds=\(requestedDuration)")
            print("actual_elapsed_seconds=\(report.actualElapsedSeconds)")
            print("system=\(result.system.file.path)")
            print("system_bytes=\(systemSize)")
            print("system_sample_rate=\(result.system.metadata.sampleRate ?? 0)")
            print("system_channel_count=\(result.system.metadata.channelCount ?? 0)")
            print("system_duration_seconds=\(result.system.metadata.duration ?? 0)")
            print("system_first_sample_time=\(result.system.metadata.firstSamplePresentationTime ?? 0)")
            print("system_first_sample_offset_seconds=\(result.system.metadata.firstSampleOffset ?? 0)")
            print("system_timing_confidence=\(result.system.metadata.timingConfidence.rawValue)")
            print("microphone=\(result.microphone.file.path)")
            print("microphone_bytes=\(microphoneSize)")
            print("microphone_sample_rate=\(result.microphone.metadata.sampleRate ?? 0)")
            print("microphone_channel_count=\(result.microphone.metadata.channelCount ?? 0)")
            print("microphone_duration_seconds=\(result.microphone.metadata.duration ?? 0)")
            print("microphone_first_sample_time=\(result.microphone.metadata.firstSamplePresentationTime ?? 0)")
            print("microphone_first_sample_offset_seconds=\(result.microphone.metadata.firstSampleOffset ?? 0)")
            print("microphone_start_offset_uncertainty_seconds=\(assessment.startOffsetUncertaintySeconds ?? 0)")
            print("microphone_timing_confidence=\(result.microphone.metadata.timingConfidence.rawValue)")
            if let startOffset = assessment.startOffsetSeconds {
                print("start_offset_seconds=\(startOffset)")
            }
            if let drift = assessment.estimatedDriftSeconds {
                print("estimated_drift_seconds=\(drift)")
            }
            if let tolerance = assessment.driftToleranceSeconds {
                print("drift_tolerance_seconds=\(tolerance)")
            }
            print("option_b_passed=\(assessment.gatePassed)")
            print("merge_policy=timestamp_offsets")
            print("metadata=\(metadataURL.path)")
            guard assessment.gatePassed else {
                Foundation.exit(2)
            }
        } catch {
            _ = try? await recorder.stopWithMetadata()
            fputs("unified-capture-smoke failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func requestedDurationSeconds() -> TimeInterval {
        let explicit = CommandLine.arguments.dropFirst().first.flatMap(TimeInterval.init)
        let environment = ProcessInfo.processInfo.environment["VOICE_CAPTIONER_UNIFIED_CAPTURE_SECONDS"].flatMap(TimeInterval.init)
        return max(explicit ?? environment ?? 30, 1)
    }

    private static func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                throw MicrophoneRecorderError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw MicrophoneRecorderError.microphonePermissionDenied
        @unknown default:
            throw MicrophoneRecorderError.microphonePermissionDenied
        }
    }

    private static func fileSize(_ url: URL) throws -> Int {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.intValue ?? 0
    }

    private static func writeReport(_ report: UnifiedCaptureSmokeReport, to url: URL) throws {
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
