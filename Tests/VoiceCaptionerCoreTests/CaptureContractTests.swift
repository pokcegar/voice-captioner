import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("Capture contract")
struct CaptureContractTests {
    @Test func captureResultCodableRoundTripPreservesTrackTimingDriftAndFailures() throws {
        let result = CaptureResult(
            handle: CaptureHandle(id: "capture-1"),
            status: .interrupted,
            tracks: [
                AudioTrack(
                    id: "system",
                    kind: .system,
                    relativePath: "audio/system.wav",
                    sampleRate: 48_000,
                    channelCount: 2,
                    firstSampleTime: 123.456,
                    startOffset: 0,
                    startOffsetUncertainty: nil,
                    timingConfidence: .observed,
                    duration: 30.000
                ),
                AudioTrack(
                    id: "microphone",
                    kind: .microphone,
                    relativePath: "audio/microphone.wav",
                    sampleRate: 48_000,
                    channelCount: 1,
                    firstSampleTime: nil,
                    startOffset: 0.125,
                    startOffsetUncertainty: 0.250,
                    timingConfidence: .inferred,
                    duration: 29.940
                )
            ],
            drift: CaptureDriftReport(
                measuredOverSeconds: 30,
                estimatedDriftSeconds: 0.060,
                toleranceSeconds: 0.100,
                basis: "file duration"
            ),
            failures: [
                CaptureFailure(capability: "systemAudio", message: "partial finalization", recoverable: true)
            ]
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CaptureResult.self, from: data)

        #expect(decoded == result)
        #expect(decoded.status == .interrupted)
        #expect(decoded.failures == [CaptureFailure(capability: "systemAudio", message: "partial finalization", recoverable: true)])
        #expect(decoded.drift?.estimatedDriftSeconds == 0.060)
        #expect(decoded.tracks.first { $0.kind == AudioTrackKind.system }?.timingConfidence == .observed)
        #expect(decoded.tracks.first { $0.kind == AudioTrackKind.microphone }?.startOffsetUncertainty == 0.250)
    }

    @Test func permissionStatusCarriesCapabilitySpecificReadiness() throws {
        let status = PermissionStatus(
            microphone: .ready,
            systemAudio: CaptureCapabilityStatus(readiness: .notDetermined, message: "Awaiting ScreenCaptureKit smoke", recoverable: true),
            outputFolder: CaptureCapabilityStatus(readiness: .unavailable, message: "Folder is not writable", recoverable: true),
            sandboxEntitlement: CaptureCapabilityStatus(readiness: .unknown, message: "SwiftPM run", recoverable: true),
            model: CaptureCapabilityStatus(readiness: .notConfigured, message: "No local model", recoverable: true)
        )

        #expect(status.microphone.readiness.isReady)
        #expect(status.microphoneGranted)
        #expect(!status.screenCaptureGranted)
        #expect(status.systemAudio.readiness == .notDetermined)
        #expect(status.outputFolder.readiness == .unavailable)
        #expect(status.sandboxEntitlement.readiness == .unknown)
        #expect(status.model.readiness == .notConfigured)
        #expect(status.outputFolder.message == "Folder is not writable")
    }

    @Test func legacyPermissionInitializerMapsToCapabilityStatuses() {
        let denied = PermissionStatus(microphoneGranted: false, screenCaptureGranted: false)
        let granted = PermissionStatus(microphoneGranted: true, screenCaptureGranted: true)

        #expect(denied.microphone.readiness == .denied)
        #expect(denied.systemAudio.readiness == .notDetermined)
        #expect(!denied.microphoneGranted)
        #expect(!denied.screenCaptureGranted)
        #expect(granted.microphone.readiness == .ready)
        #expect(granted.systemAudio.readiness == .ready)
        #expect(granted.microphoneGranted)
        #expect(granted.screenCaptureGranted)
    }
}

@Suite("CaptureSessionCoordinator")
struct CaptureSessionCoordinatorTests {
    @Test func fakeRecordersFinalizeMetadataCaptureResultAndDrift() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try MeetingStore().createMeeting(
            outputRoot: root,
            title: "Coordinator",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let metadataReader = MeetingStore()
        let system = FakeCaptureSourceRecorder(
            kind: .system,
            startedTrack: AudioTrack(
                id: "system",
                kind: .system,
                relativePath: "audio/system.wav",
                sampleRate: 48_000,
                channelCount: 2,
                firstSampleTime: 10,
                startOffset: 0,
                timingConfidence: .observed
            ),
            stoppedTrack: AudioTrack(
                id: "system",
                kind: .system,
                relativePath: "audio/system.wav",
                sampleRate: 48_000,
                channelCount: 2,
                firstSampleTime: 10,
                startOffset: 0,
                timingConfidence: .observed,
                duration: 30.000
            )
        )
        let microphone = FakeCaptureSourceRecorder(
            kind: .microphone,
            startedTrack: AudioTrack(
                id: "microphone",
                kind: .microphone,
                relativePath: "audio/microphone.wav",
                startOffset: 0.100,
                startOffsetUncertainty: 0.250,
                timingConfidence: .inferred
            ),
            stoppedTrack: AudioTrack(
                id: "microphone",
                kind: .microphone,
                relativePath: "audio/microphone.wav",
                sampleRate: 48_000,
                channelCount: 1,
                firstSampleTime: nil,
                startOffset: 0.100,
                startOffsetUncertainty: 0.250,
                timingConfidence: .inferred,
                duration: 29.940
            )
        )
        let coordinator = CaptureSessionCoordinator(
            recorders: [system, microphone],
            store: MeetingStore(),
            driftToleranceSeconds: 0.100
        )

        let handle = try await coordinator.start(
            session: CaptureSessionConfig(outputFolder: folder),
            now: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let recordingMetadata = try metadataReader.readMetadata(at: folder.metadataURL)

        #expect(recordingMetadata.status == MeetingStatus.recording)
        #expect(recordingMetadata.sessionClockStart == Date(timeIntervalSince1970: 1_800_000_100))
        #expect(recordingMetadata.tracks.first { $0.kind == AudioTrackKind.system }?.timingConfidence == .observed)
        #expect(recordingMetadata.tracks.first { $0.kind == AudioTrackKind.microphone }?.timingConfidence == .inferred)

        let result = try await coordinator.stop(handle, now: Date(timeIntervalSince1970: 1_800_000_130))
        let finalizedMetadata = try metadataReader.readMetadata(at: folder.metadataURL)

        #expect(result.status == MeetingStatus.complete)
        #expect(result.failures.isEmpty)
        #expect(result.tracks.map { $0.kind } == [.system, .microphone])
        #expect(result.drift?.measuredOverSeconds == 30.000)
        #expect(abs((result.drift?.estimatedDriftSeconds ?? -1) - 0.060) < 0.000_001)
        #expect(result.drift?.toleranceSeconds == 0.100)
        #expect(result.drift?.basis == "file duration")
        #expect(finalizedMetadata.status == MeetingStatus.complete)
        #expect(finalizedMetadata.tracks == result.tracks)
        #expect(finalizedMetadata.tracks.first { $0.kind == AudioTrackKind.system }?.firstSampleTime == 10)
        #expect(finalizedMetadata.tracks.first { $0.kind == AudioTrackKind.microphone }?.startOffsetUncertainty == 0.250)

        let cached = try await coordinator.stop(handle, now: Date(timeIntervalSince1970: 1_800_000_131))
        #expect(cached == result)
    }

    @Test func recorderStartAndStopFailuresProduceInterruptedCaptureResult() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try MeetingStore().createMeeting(outputRoot: root, title: "Partial")
        let metadataReader = MeetingStore()
        let system = FakeCaptureSourceRecorder(
            kind: .system,
            startedTrack: AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", timingConfidence: .observed),
            stoppedTrack: AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", timingConfidence: .observed, duration: 5)
        )
        let microphone = FakeCaptureSourceRecorder(
            kind: .microphone,
            startedTrack: AudioTrack(id: "microphone", kind: .microphone, relativePath: "audio/microphone.wav"),
            stoppedTrack: AudioTrack(id: "microphone", kind: .microphone, relativePath: "audio/microphone.wav"),
            startError: FakeRecorderError.startDenied,
            stopError: FakeRecorderError.stopFailed
        )
        let coordinator = CaptureSessionCoordinator(recorders: [system, microphone], store: MeetingStore())

        let handle = try await coordinator.start(session: CaptureSessionConfig(outputFolder: folder))
        let startMetadata = try metadataReader.readMetadata(at: folder.metadataURL)
        #expect(startMetadata.status == MeetingStatus.interrupted)

        let result = try await coordinator.stop(handle)
        let finalizedMetadata = try metadataReader.readMetadata(at: folder.metadataURL)

        #expect(result.status == MeetingStatus.interrupted)
        #expect(result.failures.count == 2)
        #expect(result.failures.map { $0.capability } == ["microphone", "microphone"])
        #expect(result.failures.allSatisfy { $0.recoverable })
        #expect(result.tracks.contains { $0.kind == AudioTrackKind.system })
        #expect(finalizedMetadata.status == MeetingStatus.interrupted)
    }

    @Test func interruptPersistsFailureAndReturnsPartialResult() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writerStore = MeetingStore()
        let folder = try writerStore.createMeeting(outputRoot: root, title: "Interrupted")
        let metadataReader = MeetingStore()
        let coordinator = CaptureSessionCoordinator(
            recorders: [
                FakeCaptureSourceRecorder(
                    kind: .system,
                    startedTrack: AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", timingConfidence: .observed),
                    stoppedTrack: AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", timingConfidence: .observed, duration: 1)
                )
            ],
            store: MeetingStore()
        )
        let handle = try await coordinator.start(session: CaptureSessionConfig(outputFolder: folder))
        let failure = CaptureFailure(capability: "outputFolder", message: "Lost write access", recoverable: true)

        let result = try await coordinator.interrupt(handle, failure: failure)
        let metadata = try metadataReader.readMetadata(at: folder.metadataURL)

        #expect(result.status == MeetingStatus.interrupted)
        #expect(result.failures == [failure])
        #expect(metadata.status == MeetingStatus.interrupted)
    }

    @Test func noRecordersKeepCaptureGateClosedForTests() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try MeetingStore().createMeeting(outputRoot: root, title: "No Recorders")
        let coordinator = CaptureSessionCoordinator(recorders: [])

        await #expect(throws: CaptureSessionCoordinatorError.noRecorders) {
            _ = try await coordinator.start(session: CaptureSessionConfig(outputFolder: folder))
        }
    }
}

private enum FakeRecorderError: Error, Equatable {
    case startDenied
    case stopFailed
}

private actor FakeCaptureSourceRecorder: CaptureSourceRecorder {
    nonisolated let kind: AudioTrackKind
    private let startedTrack: AudioTrack
    private let stoppedTrack: AudioTrack
    private let startError: FakeRecorderError?
    private let stopError: FakeRecorderError?

    init(
        kind: AudioTrackKind,
        startedTrack: AudioTrack,
        stoppedTrack: AudioTrack,
        startError: FakeRecorderError? = nil,
        stopError: FakeRecorderError? = nil
    ) {
        self.kind = kind
        self.startedTrack = startedTrack
        self.stoppedTrack = stoppedTrack
        self.startError = startError
        self.stopError = stopError
    }

    func start(outputURL: URL, deviceID: String?, sessionStart: Date) async throws -> AudioTrack {
        if let startError {
            throw startError
        }
        return startedTrack
    }

    func stop() async throws -> AudioTrack {
        if let stopError {
            throw stopError
        }
        return stoppedTrack
    }
}
