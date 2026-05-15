import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("CaptureGateAssessment")
struct CaptureGateAssessmentTests {
    @Test func passesWithObservedSystemInferredMicrophoneBoundedUncertaintyAndLowDrift() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let system = recordingMetadata(
            kind: .system,
            startedAt: start,
            firstSampleObservedAt: start.addingTimeInterval(0.040),
            timingConfidence: .observed,
            duration: 30.000
        )
        let microphone = recordingMetadata(
            kind: .microphone,
            startedAt: start,
            firstSampleObservedAt: start.addingTimeInterval(0.100),
            timingConfidence: .inferred,
            duration: 29.940
        )

        let assessment = CaptureGateAssessment.evaluate(
            systemSize: 614_656,
            microphoneSize: 579_584,
            system: system,
            microphone: microphone
        )

        #expect(assessment.gatePassed)
        #expect(abs((assessment.startOffsetSeconds ?? 99) + 0.060) < 0.000_001)
        #expect(assessment.startOffsetUncertaintySeconds == 0.250)
        #expect(abs((assessment.estimatedDriftSeconds ?? -1) - 0.060) < 0.000_001)
        #expect(abs((assessment.driftToleranceSeconds ?? -1) - 0.110) < 0.000_001)
        #expect(assessment.mergePolicy.contains("timestamp offsets"))
        #expect(assessment.derivedMixedAudioPolicy.contains("silence padding"))
    }

    @Test func failsWhenDriftExceedsThreshold() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let system = recordingMetadata(
            kind: .system,
            startedAt: start,
            firstSampleObservedAt: start,
            timingConfidence: .observed,
            duration: 30.000
        )
        let microphone = recordingMetadata(
            kind: .microphone,
            startedAt: start,
            firstSampleObservedAt: start,
            timingConfidence: .inferred,
            duration: 29.850
        )

        let assessment = CaptureGateAssessment.evaluate(
            systemSize: 1,
            microphoneSize: 1,
            system: system,
            microphone: microphone
        )

        #expect(!assessment.gatePassed)
        #expect(abs((assessment.estimatedDriftSeconds ?? -1) - 0.150) < 0.000_001)
        #expect(assessment.gateSummary.contains("keep native provider gated"))
    }

    @Test func failsWhenTimingUncertaintyIsUnknown() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let system = recordingMetadata(
            kind: .system,
            startedAt: start,
            firstSampleObservedAt: nil,
            timingConfidence: .unknown,
            duration: 30.000
        )
        let microphone = recordingMetadata(
            kind: .microphone,
            startedAt: start,
            firstSampleObservedAt: start,
            timingConfidence: .inferred,
            duration: 30.000
        )

        let assessment = CaptureGateAssessment.evaluate(
            systemSize: 1,
            microphoneSize: 1,
            system: system,
            microphone: microphone
        )

        #expect(!assessment.gatePassed)
        #expect(assessment.startOffsetSeconds == nil)
        #expect(assessment.startOffsetUncertaintySeconds == nil)
    }
}

private func recordingMetadata(
    kind: AudioTrackKind,
    startedAt: Date,
    firstSampleObservedAt: Date?,
    timingConfidence: RecorderTimingConfidence,
    duration: TimeInterval
) -> AudioRecordingMetadata {
    AudioRecordingMetadata(
        kind: kind,
        filePath: ".tmp/capture-smoke/\(kind.rawValue).wav",
        sampleRate: 48_000,
        channelCount: kind == .system ? 2 : 1,
        duration: duration,
        recorderStartedAt: startedAt,
        recorderStoppedAt: startedAt.addingTimeInterval(duration),
        firstSamplePresentationTime: kind == .system ? 12.345 : nil,
        firstSampleObservedAt: firstSampleObservedAt,
        firstSampleOffset: firstSampleObservedAt?.timeIntervalSince(startedAt),
        timingConfidence: timingConfidence,
        timingBasis: "test fixture"
    )
}
