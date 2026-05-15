import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

public enum UnifiedScreenCaptureAudioRecorderError: Error, Equatable {
    case noDisplayAvailable
    case cannotAddStreamOutput(String)
    case alreadyRecording
    case notRecording
    case writerCannotAddInput(AudioTrackKind)
    case writerFailed(AudioTrackKind, String)
    case outputFileMissing(URL)
    case missingTrack(AudioTrackKind)
}

public struct UnifiedAudioRecordingResult: Equatable, Sendable {
    public var system: AudioRecordingResult
    public var microphone: AudioRecordingResult

    public init(system: AudioRecordingResult, microphone: AudioRecordingResult) {
        self.system = system
        self.microphone = microphone
    }
}

public final class UnifiedScreenCaptureAudioRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    private final class TrackWriterState {
        let kind: AudioTrackKind
        let outputURL: URL
        var writer: AVAssetWriter?
        var input: AVAssetWriterInput?
        var firstSamplePresentationTime: CMTime?
        var firstSampleObservedAt: Date?
        var recorderStartedAt: Date?
        var recorderStoppedAt: Date?

        init(kind: AudioTrackKind, outputURL: URL) {
            self.kind = kind
            self.outputURL = outputURL
        }
    }

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "voice-captioner.unified-screen-capture-audio")
    private var states: [AudioTrackKind: TrackWriterState] = [:]
    private var sessionStartedAt: Date?

    public override init() {
        super.init()
    }

    public func start(systemURL: URL, microphoneURL: URL, microphoneDeviceID: String? = nil) async throws {
        guard stream == nil else { throw UnifiedScreenCaptureAudioRecorderError.alreadyRecording }
        try prepareOutput(systemURL)
        try prepareOutput(microphoneURL)

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw UnifiedScreenCaptureAudioRecorderError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.microphoneCaptureDeviceID = microphoneDeviceID
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        } catch {
            throw UnifiedScreenCaptureAudioRecorderError.cannotAddStreamOutput(error.localizedDescription)
        }

        let startedAt = Date()
        queue.sync {
            self.states = [
                .system: TrackWriterState(kind: .system, outputURL: systemURL),
                .microphone: TrackWriterState(kind: .microphone, outputURL: microphoneURL)
            ]
            self.states[.system]?.recorderStartedAt = startedAt
            self.states[.microphone]?.recorderStartedAt = startedAt
            self.sessionStartedAt = startedAt
        }
        self.stream = stream
        try await stream.startCapture()
    }

    public func stopWithMetadata() async throws -> UnifiedAudioRecordingResult {
        guard let stream else { throw UnifiedScreenCaptureAudioRecorderError.notRecording }
        try await stream.stopCapture()
        let stoppedAt = Date()

        let snapshot: [AudioTrackKind: TrackWriterState] = queue.sync {
            for state in states.values {
                state.recorderStoppedAt = stoppedAt
                state.input?.markAsFinished()
            }
            return states
        }

        let system = try await finish(state: requiredState(.system, in: snapshot))
        let microphone = try await finish(state: requiredState(.microphone, in: snapshot))

        self.stream = nil
        queue.sync {
            self.states = [:]
            self.sessionStartedAt = nil
        }

        return UnifiedAudioRecordingResult(system: system, microphone: microphone)
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        let kind: AudioTrackKind
        switch type {
        case .audio:
            kind = .system
        case .microphone:
            kind = .microphone
        default:
            return
        }

        guard let state = states[kind] else { return }
        do {
            try append(sampleBuffer, to: state)
        } catch {
            // The smoke will fail on stop if the writer cannot complete or output is missing.
            return
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to state: TrackWriterState) throws {
        if state.writer == nil {
            try createWriter(for: state, sampleBuffer: sampleBuffer)
            state.firstSamplePresentationTime = sampleBuffer.presentationTimeStamp
            state.firstSampleObservedAt = Date()
            state.writer?.startWriting()
            state.writer?.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
        }
        guard state.input?.isReadyForMoreMediaData == true else { return }
        state.input?.append(sampleBuffer)
    }

    private func createWriter(for state: TrackWriterState, sampleBuffer: CMSampleBuffer) throws {
        let writer = try AVAssetWriter(outputURL: state.outputURL, fileType: .wav)
        let format = sampleBuffer.formatDescription.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let sampleRate = format?.mSampleRate ?? 48_000
        let channels = Int(format?.mChannelsPerFrame ?? (state.kind == .system ? 2 : 1))
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw UnifiedScreenCaptureAudioRecorderError.writerCannotAddInput(state.kind)
        }
        writer.add(input)
        state.writer = writer
        state.input = input
    }

    private func finish(state: TrackWriterState) async throws -> AudioRecordingResult {
        guard let writer = state.writer else {
            throw UnifiedScreenCaptureAudioRecorderError.missingTrack(state.kind)
        }
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            throw UnifiedScreenCaptureAudioRecorderError.writerFailed(
                state.kind,
                writer.error?.localizedDescription ?? "unknown"
            )
        }
        guard FileManager.default.fileExists(atPath: state.outputURL.path) else {
            throw UnifiedScreenCaptureAudioRecorderError.outputFileMissing(state.outputURL)
        }
        let fileMetadata = try inspectAudioFile(at: state.outputURL)
        let startedAt = state.recorderStartedAt ?? state.firstSampleObservedAt ?? Date()
        let stoppedAt = state.recorderStoppedAt ?? Date()
        let metadata = AudioRecordingMetadata(
            kind: state.kind,
            filePath: state.outputURL.path,
            sampleRate: fileMetadata.sampleRate,
            channelCount: fileMetadata.channelCount,
            duration: fileMetadata.duration,
            recorderStartedAt: startedAt,
            recorderStoppedAt: stoppedAt,
            firstSamplePresentationTime: state.firstSamplePresentationTime?.seconds,
            firstSampleObservedAt: state.firstSampleObservedAt,
            firstSampleOffset: state.firstSampleObservedAt?.timeIntervalSince(startedAt),
            timingConfidence: state.firstSamplePresentationTime == nil ? .unknown : .observed,
            timingBasis: "ScreenCaptureKit \(state.kind.rawValue) CMSampleBuffer presentationTimeStamp plus WAV file inspection"
        )
        return AudioRecordingResult(file: state.outputURL, metadata: metadata)
    }

    private func requiredState(_ kind: AudioTrackKind, in states: [AudioTrackKind: TrackWriterState]) throws -> TrackWriterState {
        guard let state = states[kind] else {
            throw UnifiedScreenCaptureAudioRecorderError.missingTrack(kind)
        }
        return state
    }

    private func prepareOutput(_ outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
    }
}
