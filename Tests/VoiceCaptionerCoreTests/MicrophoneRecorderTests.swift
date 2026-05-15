import AVFoundation
import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("MicrophoneRecorder")
struct MicrophoneRecorderTests {
    @Test func stopWithoutStartThrows() async throws {
        let recorder = MicrophoneRecorder()

        await #expect(throws: MicrophoneRecorderError.notRecording) {
            _ = try await recorder.stop()
        }
    }

    @Test func startWithoutPermissionThrows() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) != .authorized else {
            return
        }
        let recorder = MicrophoneRecorder()
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "microphone.wav")

        #expect(throws: MicrophoneRecorderError.microphonePermissionDenied) {
            try recorder.start(outputURL: output)
        }
    }
}
