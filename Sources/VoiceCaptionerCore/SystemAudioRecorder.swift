import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

public enum RecorderTimingConfidence: String, Codable, Equatable, Sendable {
    case observed
    case inferred
    case unknown
}

public struct AudioRecordingMetadata: Codable, Equatable, Sendable {
    public var kind: AudioTrackKind
    public var filePath: String
    public var sampleRate: Double?
    public var channelCount: Int?
    public var duration: TimeInterval?
    public var recorderStartedAt: Date
    public var recorderStoppedAt: Date
    public var firstSamplePresentationTime: TimeInterval?
    public var firstSampleObservedAt: Date?
    public var firstSampleOffset: TimeInterval?
    public var timingConfidence: RecorderTimingConfidence
    public var timingBasis: String

    public init(
        kind: AudioTrackKind,
        filePath: String,
        sampleRate: Double?,
        channelCount: Int?,
        duration: TimeInterval?,
        recorderStartedAt: Date,
        recorderStoppedAt: Date,
        firstSamplePresentationTime: TimeInterval?,
        firstSampleObservedAt: Date?,
        firstSampleOffset: TimeInterval?,
        timingConfidence: RecorderTimingConfidence,
        timingBasis: String
    ) {
        self.kind = kind
        self.filePath = filePath
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.duration = duration
        self.recorderStartedAt = recorderStartedAt
        self.recorderStoppedAt = recorderStoppedAt
        self.firstSamplePresentationTime = firstSamplePresentationTime
        self.firstSampleObservedAt = firstSampleObservedAt
        self.firstSampleOffset = firstSampleOffset
        self.timingConfidence = timingConfidence
        self.timingBasis = timingBasis
    }
}

public struct AudioRecordingResult: Equatable, Sendable {
    public var file: URL
    public var metadata: AudioRecordingMetadata

    public init(file: URL, metadata: AudioRecordingMetadata) {
        self.file = file
        self.metadata = metadata
    }
}

public enum SystemAudioRecorderError: Error, Equatable {
    case noDisplayAvailable
    case cannotAddStreamOutput(String)
    case writerCannotAddInput
    case alreadyRecording
    case notRecording
    case writerFailed(String)
    case outputFileMissing(URL)
}

public final class SystemAudioRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "voice-captioner.system-audio")
    private var didStartSession = false
    private var outputURL: URL?
    private var recorderStartedAt: Date?
    private var firstSamplePresentationTime: CMTime?
    private var firstSampleObservedAt: Date?
    private var lastFirstSamplePresentationTime: CMTime?

    public override init() {
        super.init()
    }

    public var firstSampleTime: TimeInterval? {
        queue.sync {
            (firstSamplePresentationTime ?? lastFirstSamplePresentationTime)?.seconds
        }
    }

    public func start(outputURL: URL) async throws {
        guard stream == nil else { throw SystemAudioRecorderError.alreadyRecording }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw SystemAudioRecorderError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        } catch {
            throw SystemAudioRecorderError.cannotAddStreamOutput(error.localizedDescription)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw SystemAudioRecorderError.writerCannotAddInput
        }
        writer.add(input)

        self.outputURL = outputURL
        self.stream = stream
        self.writer = writer
        self.writerInput = input
        self.didStartSession = false
        self.recorderStartedAt = Date()
        self.firstSamplePresentationTime = nil
        self.firstSampleObservedAt = nil
        self.lastFirstSamplePresentationTime = nil

        try await stream.startCapture()
    }

    public func stop() async throws -> URL {
        try await stopWithMetadata().file
    }

    public func stopWithMetadata() async throws -> AudioRecordingResult {
        guard let stream, let writer, let writerInput, let outputURL else {
            throw SystemAudioRecorderError.notRecording
        }
        try await stream.stopCapture()
        let recorderStoppedAt = Date()
        let recorderStartedAt = self.recorderStartedAt ?? recorderStoppedAt
        let timingSnapshot = queue.sync {
            (
                firstSamplePresentationTime: self.firstSamplePresentationTime,
                firstSampleObservedAt: self.firstSampleObservedAt
            )
        }
        writerInput.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        self.stream = nil
        self.writer = nil
        self.writerInput = nil
        self.outputURL = nil
        self.didStartSession = false
        self.recorderStartedAt = nil
        self.lastFirstSamplePresentationTime = timingSnapshot.firstSamplePresentationTime
        self.firstSamplePresentationTime = nil
        self.firstSampleObservedAt = nil

        guard writer.status == .completed else {
            throw SystemAudioRecorderError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw SystemAudioRecorderError.outputFileMissing(outputURL)
        }
        let fileMetadata = try inspectAudioFile(at: outputURL)
        let firstSampleObservedAt = timingSnapshot.firstSampleObservedAt
        let metadata = AudioRecordingMetadata(
            kind: .system,
            filePath: outputURL.path,
            sampleRate: fileMetadata.sampleRate,
            channelCount: fileMetadata.channelCount,
            duration: fileMetadata.duration,
            recorderStartedAt: recorderStartedAt,
            recorderStoppedAt: recorderStoppedAt,
            firstSamplePresentationTime: timingSnapshot.firstSamplePresentationTime?.seconds,
            firstSampleObservedAt: firstSampleObservedAt,
            firstSampleOffset: firstSampleObservedAt?.timeIntervalSince(recorderStartedAt),
            timingConfidence: timingSnapshot.firstSamplePresentationTime == nil ? .unknown : .observed,
            timingBasis: "ScreenCaptureKit audio CMSampleBuffer presentationTimeStamp plus WAV file inspection"
        )
        return AudioRecordingResult(file: outputURL, metadata: metadata)
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              sampleBuffer.isValid,
              let writer,
              let writerInput
        else {
            return
        }

        let presentationTime = sampleBuffer.presentationTimeStamp
        if !didStartSession {
            writer.startWriting()
            writer.startSession(atSourceTime: presentationTime)
            didStartSession = true
            firstSamplePresentationTime = presentationTime
            firstSampleObservedAt = Date()
        }
        guard writerInput.isReadyForMoreMediaData else { return }
        writerInput.append(sampleBuffer)
    }
}

func inspectAudioFile(at url: URL) throws -> (sampleRate: Double, channelCount: Int, duration: TimeInterval) {
    let audioFile = try AVAudioFile(forReading: url)
    let format = audioFile.fileFormat
    let sampleRate = format.sampleRate
    let channelCount = Int(format.channelCount)
    let duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0
    return (sampleRate, channelCount, duration)
}
