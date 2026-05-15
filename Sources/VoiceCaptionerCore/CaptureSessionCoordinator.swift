import AVFoundation
import Foundation

public protocol CaptureSourceRecorder: Sendable {
    var kind: AudioTrackKind { get }
    func start(outputURL: URL, deviceID: String?, sessionStart: Date) async throws -> AudioTrack
    func stop() async throws -> AudioTrack
}

public enum CaptureSessionCoordinatorError: Error, Equatable {
    case handleNotFound(CaptureHandle)
    case alreadyFinalized(CaptureHandle)
    case noRecorders
}

public final class CaptureSessionCoordinator: @unchecked Sendable {
    public let driftToleranceSeconds: TimeInterval

    private let recorders: [any CaptureSourceRecorder]
    private let store: MeetingStore
    private var sessions: [String: ActiveCaptureSession] = [:]

    public init(
        recorders: [any CaptureSourceRecorder],
        store: MeetingStore = MeetingStore(),
        driftToleranceSeconds: TimeInterval = 0.100
    ) {
        self.recorders = recorders
        self.store = store
        self.driftToleranceSeconds = driftToleranceSeconds
    }

    public func start(session config: CaptureSessionConfig, now: Date = Date()) async throws -> CaptureHandle {
        guard !recorders.isEmpty else { throw CaptureSessionCoordinatorError.noRecorders }

        let handle = CaptureHandle(id: UUID().uuidString)
        var metadata = config.outputFolder.metadata
        metadata.status = .recording
        metadata.sessionClockStart = now
        metadata.updatedAt = now
        try store.writeMetadata(metadata, to: config.outputFolder.metadataURL)

        var startedTracks: [AudioTrack] = []
        var failures: [CaptureFailure] = []
        do {
            for recorder in recorders {
                let outputURL = config.outputFolder.audioDirectory.appending(
                    path: "\(recorder.kind.rawValue).wav",
                    directoryHint: .notDirectory
                )
                do {
                    let track = try await recorder.start(
                        outputURL: outputURL,
                        deviceID: config.microphoneDeviceID,
                        sessionStart: now
                    )
                    startedTracks.append(track)
                } catch {
                    failures.append(CaptureFailure(
                        capability: recorder.kind.rawValue,
                        message: String(describing: error),
                        recoverable: true
                    ))
                }
            }

            metadata.tracks = mergeTracks(existing: metadata.tracks, updates: startedTracks)
            metadata.status = failures.isEmpty ? .recording : .interrupted
            metadata.updatedAt = Date()
            try store.writeMetadata(metadata, to: config.outputFolder.metadataURL)

            sessions[handle.id] = ActiveCaptureSession(
                handle: handle,
                config: config,
                metadata: metadata,
                startedAt: now,
                failures: failures,
                finalizedResult: nil
            )
            return handle
        } catch {
            sessions.removeValue(forKey: handle.id)
            throw error
        }
    }

    public func stop(_ handle: CaptureHandle, now: Date = Date()) async throws -> CaptureResult {
        guard var active = sessions[handle.id] else {
            throw CaptureSessionCoordinatorError.handleNotFound(handle)
        }
        if let finalizedResult = active.finalizedResult {
            return finalizedResult
        }

        var metadata = active.metadata
        metadata.status = .finalizing
        metadata.updatedAt = now
        try store.writeMetadata(metadata, to: active.config.outputFolder.metadataURL)

        var finalizedTracks: [AudioTrack] = []
        var failures = active.failures
        for recorder in recorders {
            do {
                let track = try await recorder.stop()
                finalizedTracks.append(track)
            } catch {
                failures.append(CaptureFailure(
                    capability: recorder.kind.rawValue,
                    message: String(describing: error),
                    recoverable: true
                ))
            }
        }

        metadata.tracks = mergeTracks(existing: metadata.tracks, updates: finalizedTracks)
        let drift = Self.driftReport(for: metadata.tracks, toleranceSeconds: driftToleranceSeconds)
        let status: MeetingStatus = failures.isEmpty ? .complete : .interrupted
        metadata.status = status
        metadata.updatedAt = now
        try store.writeMetadata(metadata, to: active.config.outputFolder.metadataURL)

        let result = CaptureResult(
            handle: handle,
            status: status,
            tracks: metadata.tracks,
            drift: drift,
            failures: failures
        )
        active.metadata = metadata
        active.failures = failures
        active.finalizedResult = result
        sessions[handle.id] = active
        return result
    }

    public func interrupt(_ handle: CaptureHandle, failure: CaptureFailure, now: Date = Date()) async throws -> CaptureResult {
        guard var active = sessions[handle.id] else {
            throw CaptureSessionCoordinatorError.handleNotFound(handle)
        }
        if let finalizedResult = active.finalizedResult {
            return finalizedResult
        }

        var metadata = active.metadata
        metadata.status = .interrupted
        metadata.updatedAt = now
        active.failures.append(failure)
        try store.writeMetadata(metadata, to: active.config.outputFolder.metadataURL)

        let result = CaptureResult(
            handle: handle,
            status: .interrupted,
            tracks: metadata.tracks,
            drift: Self.driftReport(for: metadata.tracks, toleranceSeconds: driftToleranceSeconds),
            failures: active.failures
        )
        active.metadata = metadata
        active.finalizedResult = result
        sessions[handle.id] = active
        return result
    }

    public func result(for handle: CaptureHandle) throws -> CaptureResult? {
        guard let active = sessions[handle.id] else {
            throw CaptureSessionCoordinatorError.handleNotFound(handle)
        }
        return active.finalizedResult
    }

    public static func driftReport(
        for tracks: [AudioTrack],
        toleranceSeconds: TimeInterval = 0.100
    ) -> CaptureDriftReport? {
        let sourceTracks = tracks.filter { $0.kind == .system || $0.kind == .microphone }
        guard sourceTracks.count >= 2,
              let shortest = sourceTracks.compactMap(\.duration).min(),
              let longest = sourceTracks.compactMap(\.duration).max()
        else {
            return nil
        }

        return CaptureDriftReport(
            measuredOverSeconds: longest,
            estimatedDriftSeconds: (abs(longest - shortest) * 1_000_000).rounded() / 1_000_000,
            toleranceSeconds: toleranceSeconds,
            basis: "file duration"
        )
    }

    private func mergeTracks(existing: [AudioTrack], updates: [AudioTrack]) -> [AudioTrack] {
        var merged = existing
        for update in updates {
            if let index = merged.firstIndex(where: { $0.id == update.id || $0.kind == update.kind }) {
                merged[index] = update
            } else {
                merged.append(update)
            }
        }
        return merged.sorted { lhs, rhs in
            let order: [AudioTrackKind: Int] = [.system: 0, .microphone: 1, .mixed: 2]
            return (order[lhs.kind] ?? 99, lhs.id) < (order[rhs.kind] ?? 99, rhs.id)
        }
    }
}

private struct ActiveCaptureSession: Sendable {
    var handle: CaptureHandle
    var config: CaptureSessionConfig
    var metadata: MeetingMetadata
    var startedAt: Date
    var failures: [CaptureFailure]
    var finalizedResult: CaptureResult?
}

public final class UnifiedScreenCaptureSourceRecorder: CaptureSourceRecorder, @unchecked Sendable {
    public let kind: AudioTrackKind
    private let bridge: UnifiedScreenCaptureRecorderBridge

    public init(kind: AudioTrackKind, bridge: UnifiedScreenCaptureRecorderBridge) {
        self.kind = kind
        self.bridge = bridge
    }

    public func start(outputURL: URL, deviceID: String?, sessionStart: Date) async throws -> AudioTrack {
        let audioDirectory = outputURL.deletingLastPathComponent()
        try await bridge.startIfNeeded(
            systemURL: audioDirectory.appending(path: "system.wav"),
            microphoneURL: audioDirectory.appending(path: "microphone.wav"),
            microphoneDeviceID: deviceID
        )
        return AudioTrack(
            id: kind.rawValue,
            kind: kind,
            relativePath: relativeAudioPath(for: outputURL),
            timingConfidence: .unknown
        )
    }

    public func stop() async throws -> AudioTrack {
        try await bridge.stop(kind: kind)
    }
}

public actor UnifiedScreenCaptureRecorderBridge {
    private let recorder: UnifiedScreenCaptureAudioRecorder
    private var started = false
    private var result: UnifiedAudioRecordingResult?

    public init(recorder: UnifiedScreenCaptureAudioRecorder = UnifiedScreenCaptureAudioRecorder()) {
        self.recorder = recorder
    }

    public func startIfNeeded(systemURL: URL, microphoneURL: URL, microphoneDeviceID: String?) async throws {
        guard !started else { return }
        try await recorder.start(
            systemURL: systemURL,
            microphoneURL: microphoneURL,
            microphoneDeviceID: microphoneDeviceID
        )
        started = true
    }

    public func stop(kind: AudioTrackKind) async throws -> AudioTrack {
        if result == nil {
            result = try await recorder.stopWithMetadata()
        }
        guard let result else {
            throw UnifiedScreenCaptureAudioRecorderError.missingTrack(kind)
        }
        switch kind {
        case .system:
            return audioTrack(from: result.system.metadata, fallbackURL: result.system.file)
        case .microphone:
            return audioTrack(from: result.microphone.metadata, fallbackURL: result.microphone.file)
        case .mixed:
            throw UnifiedScreenCaptureAudioRecorderError.missingTrack(.mixed)
        }
    }
}

public struct SystemAudioCaptureSourceRecorder: CaptureSourceRecorder {
    public let kind: AudioTrackKind = .system
    private let recorder: SystemAudioRecorder

    public init(recorder: SystemAudioRecorder = SystemAudioRecorder()) {
        self.recorder = recorder
    }

    public func start(outputURL: URL, deviceID: String?, sessionStart: Date) async throws -> AudioTrack {
        try await recorder.start(outputURL: outputURL)
        return AudioTrack(
            id: kind.rawValue,
            kind: kind,
            relativePath: relativeAudioPath(for: outputURL),
            sampleRate: 48_000,
            channelCount: 2,
            startOffset: 0,
            startOffsetUncertainty: nil,
            timingConfidence: .observed
        )
    }

    public func stop() async throws -> AudioTrack {
        let result = try await recorder.stopWithMetadata()
        return audioTrack(from: result.metadata, fallbackURL: result.file)
    }
}

public struct MicrophoneCaptureSourceRecorder: CaptureSourceRecorder {
    public let kind: AudioTrackKind = .microphone
    private let recorder: MicrophoneRecorder

    public init(recorder: MicrophoneRecorder = MicrophoneRecorder()) {
        self.recorder = recorder
    }

    public func start(outputURL: URL, deviceID: String?, sessionStart: Date) async throws -> AudioTrack {
        try recorder.start(outputURL: outputURL, deviceID: deviceID)
        return AudioTrack(
            id: kind.rawValue,
            kind: kind,
            relativePath: relativeAudioPath(for: outputURL),
            startOffset: max(0, Date().timeIntervalSince(sessionStart)),
            startOffsetUncertainty: 0.250,
            timingConfidence: .inferred
        )
    }

    public func stop() async throws -> AudioTrack {
        let result = try await recorder.stopWithMetadata()
        return audioTrack(from: result.metadata, fallbackURL: result.file)
    }
}

private func audioTrack(from metadata: AudioRecordingMetadata, fallbackURL: URL) -> AudioTrack {
    AudioTrack(
        id: metadata.kind.rawValue,
        kind: metadata.kind,
        relativePath: relativeAudioPath(for: URL(fileURLWithPath: metadata.filePath.isEmpty ? fallbackURL.path : metadata.filePath)),
        sampleRate: metadata.sampleRate,
        channelCount: metadata.channelCount,
        firstSampleTime: metadata.firstSamplePresentationTime,
        startOffset: metadata.firstSampleOffset,
        startOffsetUncertainty: metadata.timingConfidence == .inferred ? 0.250 : nil,
        timingConfidence: TrackTimingConfidence(recordingConfidence: metadata.timingConfidence),
        duration: metadata.duration
    )
}

private extension TrackTimingConfidence {
    init(recordingConfidence: RecorderTimingConfidence) {
        switch recordingConfidence {
        case .observed: self = .observed
        case .inferred: self = .inferred
        case .unknown: self = .unknown
        }
    }
}

private func relativeAudioPath(for url: URL) -> String {
    "audio/\(url.lastPathComponent)"
}

extension MeetingStore: @unchecked Sendable {}
