import Foundation

public struct AudioDevice: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum CapabilityReadiness: String, Codable, Equatable, Sendable {
    case ready
    case denied
    case notDetermined
    case unavailable
    case notConfigured
    case unknown

    public var isReady: Bool { self == .ready }
}

public struct CaptureCapabilityStatus: Codable, Equatable, Sendable {
    public var readiness: CapabilityReadiness
    public var message: String?
    public var recoverable: Bool

    public var isReady: Bool { readiness == .ready }

    public init(readiness: CapabilityReadiness, message: String? = nil, recoverable: Bool = true) {
        self.readiness = readiness
        self.message = message
        self.recoverable = recoverable
    }

    public static var ready: CaptureCapabilityStatus {
        CaptureCapabilityStatus(readiness: .ready, message: nil, recoverable: false)
    }
}

public struct PermissionStatus: Codable, Equatable, Sendable {
    public var microphone: CaptureCapabilityStatus
    public var systemAudio: CaptureCapabilityStatus
    public var outputFolder: CaptureCapabilityStatus
    public var sandboxEntitlement: CaptureCapabilityStatus
    public var model: CaptureCapabilityStatus

    public var microphoneGranted: Bool { microphone.readiness == .ready }
    public var screenCaptureGranted: Bool { systemAudio.readiness == .ready }

    public init(
        microphone: CaptureCapabilityStatus,
        systemAudio: CaptureCapabilityStatus,
        outputFolder: CaptureCapabilityStatus = .ready,
        sandboxEntitlement: CaptureCapabilityStatus = .ready,
        model: CaptureCapabilityStatus = CaptureCapabilityStatus(readiness: .notConfigured, message: "No transcription model selected")
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.outputFolder = outputFolder
        self.sandboxEntitlement = sandboxEntitlement
        self.model = model
    }

    public init(microphoneGranted: Bool, screenCaptureGranted: Bool) {
        self.init(
            microphone: microphoneGranted ? .ready : CaptureCapabilityStatus(readiness: .denied, message: "Microphone permission is not granted"),
            systemAudio: screenCaptureGranted ? .ready : CaptureCapabilityStatus(readiness: .notDetermined, message: "Screen/system audio capture readiness has not been verified")
        )
    }
}

public struct CaptureSessionConfig: Equatable, Sendable {
    public var outputFolder: MeetingFolder
    public var microphoneDeviceID: String?
    public var captureWholeSystemAudio: Bool

    public init(outputFolder: MeetingFolder, microphoneDeviceID: String? = nil, captureWholeSystemAudio: Bool = true) {
        self.outputFolder = outputFolder
        self.microphoneDeviceID = microphoneDeviceID
        self.captureWholeSystemAudio = captureWholeSystemAudio
    }
}

public struct CaptureHandle: Codable, Equatable, Hashable, Sendable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public protocol AudioCaptureProvider: Sendable {
    func listInputs() async throws -> [AudioDevice]
    func requestPermissions() async throws -> PermissionStatus
    func start(session: CaptureSessionConfig) async throws -> CaptureHandle
    func stop(_ handle: CaptureHandle) async throws -> CaptureResult
}

public struct AudioChunk: Equatable, Sendable {
    public var track: AudioTrackKind
    public var url: URL
    /// Offset inside the chunk/source audio. Whisper output is relative to this domain.
    public var sourceStart: TimeInterval
    public var sourceEnd: TimeInterval
    /// Offset on the meeting timeline. Transcript segments must be normalized to this domain.
    public var timelineStart: TimeInterval
    public var timelineEnd: TimeInterval

    public init(
        track: AudioTrackKind,
        url: URL,
        sourceStart: TimeInterval,
        sourceEnd: TimeInterval,
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval
    ) {
        self.track = track
        self.url = url
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.timelineStart = timelineStart
        self.timelineEnd = timelineEnd
    }

    public init(track: AudioTrackKind, url: URL, start: TimeInterval, end: TimeInterval) {
        self.init(track: track, url: url, sourceStart: start, sourceEnd: end, timelineStart: start, timelineEnd: end)
    }

    public init(id: String, track: AudioTrackKind, url: URL, start: TimeInterval, end: TimeInterval) {
        self.init(track: track, url: url, start: start, end: end)
    }

    @available(*, deprecated, message: "Use sourceStart/timelineStart to avoid mixing time domains.")
    public var start: TimeInterval {
        get { timelineStart }
        set {
            sourceStart = newValue
            timelineStart = newValue
        }
    }

    @available(*, deprecated, message: "Use sourceEnd/timelineEnd to avoid mixing time domains.")
    public var end: TimeInterval {
        get { timelineEnd }
        set {
            sourceEnd = newValue
            timelineEnd = newValue
        }
    }
}

public protocol TranscriptionProvider: Sendable {
    func transcribe(chunk: AudioChunk, model: WhisperModel) async throws -> [TranscriptSegment]
}

public protocol DiarizationProvider: Sendable {
    func label(segments: [TranscriptSegment], tracks: [AudioTrack]) async throws -> [TranscriptSegment]
}

public struct TrackAwareDiarizationProvider: DiarizationProvider {
    public init() {}
    
    public func label(segments: [TranscriptSegment], tracks: [AudioTrack]) async throws -> [TranscriptSegment] {
        segments.map { segment in
            var labeled = segment
            switch segment.sourceTrack {
            case .system:
                labeled.speakerLabel = segment.speakerLabel.isEmpty ? "Remote" : segment.speakerLabel
            case .microphone:
                labeled.speakerLabel = segment.speakerLabel.isEmpty ? "Local" : segment.speakerLabel
            case .mixed:
                labeled.speakerLabel = segment.speakerLabel.isEmpty ? "Speaker" : segment.speakerLabel
            }
            return labeled
        }
    }
}
