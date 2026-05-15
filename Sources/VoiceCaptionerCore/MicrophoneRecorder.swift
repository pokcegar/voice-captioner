import AVFoundation
import Foundation

public enum MicrophoneRecorderError: Error, Equatable {
    case microphonePermissionDenied
    case deviceNotFound(String)
    case cannotAddInput
    case cannotAddOutput
    case alreadyRecording
    case notRecording
    case outputFileMissing(URL)
}

private struct MicrophoneStopPayload {
    var file: URL
    var stoppedAt: Date
}

public final class MicrophoneRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioFileOutput()
    private var continuation: CheckedContinuation<MicrophoneStopPayload, Error>?
    private var outputURL: URL?
    private var recorderStartedAt: Date?

    public override init() {
        super.init()
    }

    public func start(outputURL: URL, deviceID: String? = nil) throws {
        guard !session.isRunning else { throw MicrophoneRecorderError.alreadyRecording }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw MicrophoneRecorderError.microphonePermissionDenied
        }

        session.beginConfiguration()

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        let device = try microphoneDevice(deviceID: deviceID)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw MicrophoneRecorderError.cannotAddInput }
        session.addInput(input)

        guard session.canAddOutput(output) else { throw MicrophoneRecorderError.cannotAddOutput }
        session.addOutput(output)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        self.outputURL = outputURL
        session.commitConfiguration()
        session.startRunning()
        recorderStartedAt = Date()
        output.startRecording(to: outputURL, outputFileType: .wav, recordingDelegate: self)
    }

    public func stop() async throws -> URL {
        try await stopWithMetadata().file
    }

    public func stopWithMetadata() async throws -> AudioRecordingResult {
        guard session.isRunning, output.isRecording else { throw MicrophoneRecorderError.notRecording }
        let payload = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            output.stopRecording()
        }
        let recorderStartedAt = recorderStartedAt ?? payload.stoppedAt
        self.recorderStartedAt = nil
        let fileMetadata = try inspectAudioFile(at: payload.file)
        let metadata = AudioRecordingMetadata(
            kind: .microphone,
            filePath: payload.file.path,
            sampleRate: fileMetadata.sampleRate,
            channelCount: fileMetadata.channelCount,
            duration: fileMetadata.duration,
            recorderStartedAt: recorderStartedAt,
            recorderStoppedAt: payload.stoppedAt,
            firstSamplePresentationTime: nil,
            firstSampleObservedAt: recorderStartedAt,
            firstSampleOffset: 0,
            timingConfidence: .inferred,
            timingBasis: "AVCaptureAudioFileOutput WAV file inspection; first sample inferred from recorder start wall clock"
        )
        return AudioRecordingResult(file: payload.file, metadata: metadata)
    }

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        session.stopRunning()
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            recorderStartedAt = nil
            return
        }
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            continuation?.resume(throwing: MicrophoneRecorderError.outputFileMissing(outputFileURL))
            continuation = nil
            recorderStartedAt = nil
            return
        }
        continuation?.resume(returning: MicrophoneStopPayload(file: outputFileURL, stoppedAt: Date()))
        continuation = nil
    }

    private func microphoneDevice(deviceID: String?) throws -> AVCaptureDevice {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices

        if let deviceID {
            guard let device = devices.first(where: { $0.uniqueID == deviceID }) else {
                throw MicrophoneRecorderError.deviceNotFound(deviceID)
            }
            return device
        }

        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            return defaultDevice
        }

        guard let first = devices.first else {
            throw MicrophoneRecorderError.deviceNotFound("default")
        }
        return first
    }
}
