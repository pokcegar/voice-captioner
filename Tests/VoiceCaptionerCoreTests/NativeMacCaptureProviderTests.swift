import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("NativeMacCaptureProvider")
struct NativeMacCaptureProviderTests {
    @Test func reportsPermissionStatusWithoutPassingCaptureGate() async throws {
        let provider = NativeMacCaptureProvider()

        let status = try await provider.requestPermissions()

        #expect(status.microphoneGranted == true || status.microphoneGranted == false)
        #expect(!status.screenCaptureGranted)
    }

    @Test func listsMicrophoneInputsWithoutGlobalSetup() async throws {
        let provider = NativeMacCaptureProvider()

        let inputs = try await provider.listInputs()

        #expect(inputs.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
    }

    @Test func startThrowsUntilCaptureGatePasses() async throws {
        let provider = NativeMacCaptureProvider()
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try MeetingStore().createMeeting(outputRoot: root, title: "Gate")
        let config = CaptureSessionConfig(outputFolder: folder)

        await #expect(throws: NativeMacCaptureError.feasibilityGateNotPassed) {
            _ = try await provider.start(session: config)
        }
    }
}
