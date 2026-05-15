import Foundation

public struct CaptureGateAssessment: Codable, Equatable, Sendable {
    public static let optionADriftThresholdSeconds: TimeInterval = 0.100
    public static let optionAStartOffsetUncertaintyThresholdSeconds: TimeInterval = 0.250

    public var startOffsetSeconds: TimeInterval?
    public var startOffsetUncertaintySeconds: TimeInterval?
    public var estimatedDriftSeconds: TimeInterval?
    public var driftToleranceSeconds: TimeInterval?
    public var gatePassed: Bool
    public var mergePolicy: String
    public var derivedMixedAudioPolicy: String
    public var driftBasis: String
    public var gateSummary: String

    public init(
        startOffsetSeconds: TimeInterval?,
        startOffsetUncertaintySeconds: TimeInterval?,
        estimatedDriftSeconds: TimeInterval?,
        driftToleranceSeconds: TimeInterval?,
        gatePassed: Bool,
        mergePolicy: String,
        derivedMixedAudioPolicy: String,
        driftBasis: String,
        gateSummary: String
    ) {
        self.startOffsetSeconds = startOffsetSeconds
        self.startOffsetUncertaintySeconds = startOffsetUncertaintySeconds
        self.estimatedDriftSeconds = estimatedDriftSeconds
        self.driftToleranceSeconds = driftToleranceSeconds
        self.gatePassed = gatePassed
        self.mergePolicy = mergePolicy
        self.derivedMixedAudioPolicy = derivedMixedAudioPolicy
        self.driftBasis = driftBasis
        self.gateSummary = gateSummary
    }

    public static func evaluate(
        systemSize: Int,
        microphoneSize: Int,
        system: AudioRecordingMetadata,
        microphone: AudioRecordingMetadata
    ) -> CaptureGateAssessment {
        let startOffset = startOffsetSeconds(system: system, microphone: microphone)
        let startOffsetUncertainty = startOffsetUncertaintySeconds(system: system, microphone: microphone)
        let drift = durationDriftSeconds(system: system, microphone: microphone)
        let tolerance = drift.map { max($0 + 0.05, optionADriftThresholdSeconds) }
        let passed = optionAPass(
            systemSize: systemSize,
            microphoneSize: microphoneSize,
            system: system,
            microphone: microphone,
            startOffsetUncertainty: startOffsetUncertainty,
            drift: drift
        )

        return CaptureGateAssessment(
            startOffsetSeconds: startOffset,
            startOffsetUncertaintySeconds: startOffsetUncertainty,
            estimatedDriftSeconds: drift,
            driftToleranceSeconds: tolerance,
            gatePassed: passed,
            mergePolicy: "Transcript merge uses per-track timestamp offsets; source tracks remain unchanged.",
            derivedMixedAudioPolicy: "Derived mixed audio may use silence padding when needed; it must never replace separated source tracks.",
            driftBasis: "absolute difference between inspected WAV durations; start offset uses first observed/inferred sample wall-clock timestamps",
            gateSummary: passed
                ? "Timing smoke passed drift and start-uncertainty thresholds."
                : "Timing smoke did not satisfy all pass thresholds; keep native provider gated."
        )
    }

    public static func startOffsetSeconds(
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

    public static func startOffsetUncertaintySeconds(
        system: AudioRecordingMetadata,
        microphone: AudioRecordingMetadata
    ) -> TimeInterval? {
        guard let systemUncertainty = timingUncertaintySeconds(system.timingConfidence),
              let microphoneUncertainty = timingUncertaintySeconds(microphone.timingConfidence)
        else {
            return nil
        }
        return systemUncertainty + microphoneUncertainty
    }

    public static func durationDriftSeconds(
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

    private static func timingUncertaintySeconds(_ confidence: RecorderTimingConfidence) -> TimeInterval? {
        switch confidence {
        case .observed:
            return 0
        case .inferred:
            return optionAStartOffsetUncertaintyThresholdSeconds
        case .unknown:
            return nil
        }
    }

    private static func optionAPass(
        systemSize: Int,
        microphoneSize: Int,
        system: AudioRecordingMetadata,
        microphone: AudioRecordingMetadata,
        startOffsetUncertainty: TimeInterval?,
        drift: TimeInterval?
    ) -> Bool {
        guard systemSize > 0,
              microphoneSize > 0,
              system.sampleRate != nil,
              microphone.sampleRate != nil,
              system.channelCount != nil,
              microphone.channelCount != nil,
              system.duration != nil,
              microphone.duration != nil,
              system.timingConfidence != .unknown,
              microphone.timingConfidence != .unknown,
              let startOffsetUncertainty,
              startOffsetUncertainty <= optionAStartOffsetUncertaintyThresholdSeconds,
              let drift,
              drift <= optionADriftThresholdSeconds
        else {
            return false
        }
        return true
    }
}
