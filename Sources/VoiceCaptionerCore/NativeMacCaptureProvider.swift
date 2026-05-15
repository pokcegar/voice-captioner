import AVFoundation
import Foundation

public enum NativeMacCaptureError: Error, Equatable {
    case feasibilityGateNotPassed
}

public struct NativeMacCaptureProvider: AudioCaptureProvider {
    private let coordinator: CaptureSessionCoordinator
    private let captureGatePassed: Bool

    public init(
        coordinator: CaptureSessionCoordinator = CaptureSessionCoordinator(recorders: {
            let bridge = UnifiedScreenCaptureRecorderBridge()
            return [
                UnifiedScreenCaptureSourceRecorder(kind: .system, bridge: bridge),
                UnifiedScreenCaptureSourceRecorder(kind: .microphone, bridge: bridge)
            ]
        }()),
        captureGatePassed: Bool = false
    ) {
        self.coordinator = coordinator
        self.captureGatePassed = captureGatePassed
    }

    public func listInputs() async throws -> [AudioDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .map { AudioDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    public func requestPermissions() async throws -> PermissionStatus {
        let microphone = microphoneCapability()
        return PermissionStatus(
            microphone: microphone,
            systemAudio: CaptureCapabilityStatus(
                readiness: .notDetermined,
                message: "Screen/system audio capture readiness requires the native capture gate smoke evidence",
                recoverable: true
            ),
            outputFolder: .ready,
            sandboxEntitlement: CaptureCapabilityStatus(
                readiness: .unknown,
                message: "Sandbox/hardened-runtime entitlements are not evaluated in SwiftPM smoke mode",
                recoverable: true
            ),
            model: CaptureCapabilityStatus(
                readiness: .notConfigured,
                message: "No transcription model selected",
                recoverable: true
            )
        )
    }

    public func start(session: CaptureSessionConfig) async throws -> CaptureHandle {
        guard captureGatePassed else {
            throw NativeMacCaptureError.feasibilityGateNotPassed
        }
        return try await coordinator.start(session: session)
    }

    public func stop(_ handle: CaptureHandle) async throws -> CaptureResult {
        try await coordinator.stop(handle)
    }

    private func microphoneCapability() -> CaptureCapabilityStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .ready
        case .notDetermined:
            return CaptureCapabilityStatus(
                readiness: .notDetermined,
                message: "Microphone permission has not been requested",
                recoverable: true
            )
        case .denied, .restricted:
            return CaptureCapabilityStatus(
                readiness: .denied,
                message: "Microphone permission is denied or restricted",
                recoverable: true
            )
        @unknown default:
            return CaptureCapabilityStatus(
                readiness: .unknown,
                message: "Unknown microphone permission status",
                recoverable: true
            )
        }
    }
}
