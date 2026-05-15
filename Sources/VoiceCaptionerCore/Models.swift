import Foundation

public enum AudioTrackKind: String, Codable, Sendable, CaseIterable {
    case system
    case microphone
    case mixed
}

public enum TrackTimingConfidence: String, Codable, Sendable {
    case observed
    case inferred
    case unknown
}

public struct AudioTrack: Codable, Equatable, Sendable {
    public var id: String
    public var kind: AudioTrackKind
    public var relativePath: String
    public var sampleRate: Double?
    public var channelCount: Int?
    public var firstSampleTime: TimeInterval?
    public var startOffset: TimeInterval?
    public var startOffsetUncertainty: TimeInterval?
    public var timingConfidence: TrackTimingConfidence
    public var duration: TimeInterval?

    public init(
        id: String,
        kind: AudioTrackKind,
        relativePath: String,
        sampleRate: Double? = nil,
        channelCount: Int? = nil,
        firstSampleTime: TimeInterval? = nil,
        startOffset: TimeInterval? = nil,
        startOffsetUncertainty: TimeInterval? = nil,
        timingConfidence: TrackTimingConfidence = .unknown,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.firstSampleTime = firstSampleTime
        self.startOffset = startOffset
        self.startOffsetUncertainty = startOffsetUncertainty
        self.timingConfidence = timingConfidence
        self.duration = duration
    }
}

public enum MeetingStatus: String, Codable, Sendable {
    case recording
    case finalizing
    case complete
    case interrupted
}

public struct CaptureFailure: Codable, Equatable, Sendable {
    public var capability: String
    public var message: String
    public var recoverable: Bool

    public init(capability: String, message: String, recoverable: Bool) {
        self.capability = capability
        self.message = message
        self.recoverable = recoverable
    }
}

public struct CaptureDriftReport: Codable, Equatable, Sendable {
    public var measuredOverSeconds: TimeInterval
    public var estimatedDriftSeconds: TimeInterval
    public var toleranceSeconds: TimeInterval
    public var basis: String

    public init(
        measuredOverSeconds: TimeInterval,
        estimatedDriftSeconds: TimeInterval,
        toleranceSeconds: TimeInterval,
        basis: String
    ) {
        self.measuredOverSeconds = measuredOverSeconds
        self.estimatedDriftSeconds = estimatedDriftSeconds
        self.toleranceSeconds = toleranceSeconds
        self.basis = basis
    }
}

public struct CaptureResult: Codable, Equatable, Sendable {
    public var handle: CaptureHandle
    public var status: MeetingStatus
    public var tracks: [AudioTrack]
    public var drift: CaptureDriftReport?
    public var failures: [CaptureFailure]

    public init(
        handle: CaptureHandle,
        status: MeetingStatus,
        tracks: [AudioTrack],
        drift: CaptureDriftReport? = nil,
        failures: [CaptureFailure] = []
    ) {
        self.handle = handle
        self.status = status
        self.tracks = tracks
        self.drift = drift
        self.failures = failures
    }
}

public struct MeetingMetadata: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var status: MeetingStatus
    public var sessionClockStart: Date?
    public var transcriptionDelaySeconds: TimeInterval
    public var tracks: [AudioTrack]

    public init(
        id: String,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        status: MeetingStatus,
        sessionClockStart: Date? = nil,
        transcriptionDelaySeconds: TimeInterval = 30,
        tracks: [AudioTrack] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.sessionClockStart = sessionClockStart
        self.transcriptionDelaySeconds = transcriptionDelaySeconds
        self.tracks = tracks
    }
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var id: String
    public var sourceTrack: AudioTrackKind
    public var speakerLabel: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var isDraft: Bool

    public init(
        id: String,
        sourceTrack: AudioTrackKind,
        speakerLabel: String,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        isDraft: Bool = false
    ) {
        self.id = id
        self.sourceTrack = sourceTrack
        self.speakerLabel = speakerLabel
        self.start = start
        self.end = end
        self.text = text
        self.isDraft = isDraft
    }
}

public struct WhisperModel: Codable, Equatable, Sendable {
    public var name: String
    public var localPath: URL
    public var checksum: String?

    public init(name: String, localPath: URL, checksum: String? = nil) {
        self.name = name
        self.localPath = localPath
        self.checksum = checksum
    }
}
