import Foundation
import Testing
@testable import VoiceCaptionerAppModel
import VoiceCaptionerCore

@Suite("VoiceCaptionerAppModel")
struct VoiceCaptionerAppModelTests {
    @Test @MainActor func refreshModelsSelectsRecommendedDownloadedManifestModel() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let models = root.appending(path: "Models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        let base = models.appending(path: "ggml-base.bin", directoryHint: .notDirectory)
        let small = models.appending(path: "ggml-small.bin", directoryHint: .notDirectory)
        try Data("base".utf8).write(to: base)
        try Data("small".utf8).write(to: small)
        try Data("""
        {"filename":"ggml-small.bin","sha256":"abc","status":"downloaded"}
        """.utf8).write(to: models.appending(path: "ggml-small.manifest.json"))

        let model = VoiceCaptionerAppModel(
            outputRoot: root.appending(path: "Meetings", directoryHint: .isDirectory),
            provider: FakeAudioCaptureProvider(),
            modelsDirectory: models,
            transcriptionWorkflow: FakeTranscriptionWorkflow()
        )

        model.refreshModels()

        #expect(model.downloadedModels.map(\.model.name).contains("ggml-small"))
        #expect(model.selectedWhisperModel?.name == "ggml-small")
        #expect(model.selectedWhisperModel?.checksum == "abc")
    }

    @Test @MainActor func startStopRecordingUpdatesHistoryAndPreview() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = FakeAudioCaptureProvider()
        let model = VoiceCaptionerAppModel(
            outputRoot: root,
            meetingTitle: "Planning",
            provider: provider,
            modelsDirectory: root.appending(path: "Models", directoryHint: .isDirectory),
            transcriptionWorkflow: FakeTranscriptionWorkflow()
        )

        await model.startRecording()
        #expect(model.isRecording)
        #expect(model.activeMeeting?.metadata.title == "Planning")

        await model.stopRecording()

        #expect(!model.isRecording)
        #expect(model.meetings.count == 1)
        #expect(model.selectedMeeting?.metadata.status == .complete)
        #expect(model.rollingPreview.map(\.sourceTrack) == [.system, .microphone])
    }



    @Test @MainActor func defaultsToChineseAndSwitchesLanguageStrings() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = VoiceCaptionerAppModel(
            outputRoot: root.appending(path: "Meetings", directoryHint: .isDirectory),
            provider: FakeAudioCaptureProvider(),
            modelsDirectory: root.appending(path: "Models", directoryHint: .isDirectory),
            transcriptionWorkflow: FakeTranscriptionWorkflow(),
            defaultWhisperExecutable: nil
        )

        #expect(model.language == .zhHans)
        #expect(model.meetingTitle == "会议")
        #expect(model.strings.text(.startRecording) == "开始录音")

        model.setLanguage(.en)
        #expect(model.strings.text(.startRecording) == "Start Recording")

        model.setLanguage(.de)
        #expect(model.strings.text(.startRecording) == "Aufnahme starten")
    }

    @Test @MainActor func initializesWithBundledWhisperExecutableCandidate() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "whisper-cli", directoryHint: .notDirectory)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let model = VoiceCaptionerAppModel(
            outputRoot: root.appending(path: "Meetings", directoryHint: .isDirectory),
            provider: FakeAudioCaptureProvider(),
            modelsDirectory: root.appending(path: "Models", directoryHint: .isDirectory),
            transcriptionWorkflow: FakeTranscriptionWorkflow(),
            defaultWhisperExecutable: WhisperExecutableCandidate(url: executable, source: "bundled")
        )

        #expect(model.whisperExecutableURL == executable)
        #expect(model.whisperExecutableSource == "bundled")
    }

    @Test @MainActor func transcribeSelectedMeetingRequiresLocalExecutableAndWritesExports() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let models = root.appending(path: "Models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        let modelURL = models.appending(path: "ggml-small.bin", directoryHint: .notDirectory)
        let executable = root.appending(path: "whisper-cli", directoryHint: .notDirectory)
        try Data("model".utf8).write(to: modelURL)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        let meeting = try MeetingStore().createMeeting(outputRoot: root, title: "Transcript")
        var metadata = meeting.metadata
        metadata.status = .complete
        metadata.tracks = [
            AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0, timingConfidence: .observed, duration: 1)
        ]
        try MeetingStore().writeMetadata(metadata, to: meeting.metadataURL)
        let workflow = FakeTranscriptionWorkflow()
        let model = VoiceCaptionerAppModel(
            outputRoot: root,
            provider: FakeAudioCaptureProvider(),
            modelsDirectory: models,
            transcriptionWorkflow: workflow
        )
        model.refreshAll()
        model.setManualModel(modelURL)
        model.setWhisperExecutable(executable)

        await model.transcribeSelectedMeeting()

        #expect(model.transcriptionState == .completed(segmentCount: 1))
        #expect(model.rollingPreview.map(\.text) == ["done"])
        let exports = model.exportArtifacts()
        #expect(exports.map(\.label) == ["Markdown", "SRT", "JSON"])
        #expect(exports.allSatisfy { $0.exists })
        #expect(await workflow.runCount() == 1)
    }
}

private actor FakeTranscriptionWorkflow: TranscriptionWorkflow {
    private var runs = 0

    func runCount() -> Int { runs }

    func run(
        meeting: MeetingFolder,
        model: WhisperModel,
        whisperExecutableURL: URL,
        chunkDuration: TimeInterval
    ) async throws -> RollingTranscriptionResult {
        runs += 1
        let segment = TranscriptSegment(
            id: "final-1",
            sourceTrack: .system,
            speakerLabel: "Remote",
            start: 0,
            end: 1,
            text: "done",
            isDraft: false
        )
        try FileManager.default.createDirectory(at: meeting.transcriptDirectory, withIntermediateDirectories: true)
        try TranscriptExporter.markdown(meeting: meeting.metadata, segments: [segment])
            .write(to: meeting.transcriptDirectory.appending(path: "final.md"), atomically: true, encoding: .utf8)
        try TranscriptExporter.srt(segments: [segment])
            .write(to: meeting.transcriptDirectory.appending(path: "final.srt"), atomically: true, encoding: .utf8)
        try TranscriptExporter.json(segments: [segment])
            .write(to: meeting.transcriptDirectory.appending(path: "final.json"), options: .atomic)
        return RollingTranscriptionResult(chunks: [], rollingSegments: [segment], finalSegments: [segment])
    }
}

private final class FakeAudioCaptureProvider: AudioCaptureProvider, @unchecked Sendable {
    private let store = MeetingStore()
    private var folderByHandle: [CaptureHandle: MeetingFolder] = [:]

    func listInputs() async throws -> [AudioDevice] { [] }

    func requestPermissions() async throws -> PermissionStatus {
        PermissionStatus(microphoneGranted: true, screenCaptureGranted: true)
    }

    func start(session: CaptureSessionConfig) async throws -> CaptureHandle {
        let handle = CaptureHandle(id: UUID().uuidString)
        folderByHandle[handle] = session.outputFolder
        return handle
    }

    func stop(_ handle: CaptureHandle) async throws -> CaptureResult {
        guard var folder = folderByHandle[handle] else {
            throw CaptureSessionCoordinatorError.handleNotFound(handle)
        }
        let tracks = [
            AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0, timingConfidence: .observed, duration: 1),
            AudioTrack(id: "microphone", kind: .microphone, relativePath: "audio/microphone.wav", startOffset: 0, timingConfidence: .observed, duration: 1)
        ]
        folder.metadata.status = .complete
        folder.metadata.tracks = tracks
        try store.writeMetadata(folder.metadata, to: folder.metadataURL)
        return CaptureResult(handle: handle, status: .complete, tracks: tracks)
    }
}

private func temporaryDirectory() throws -> URL {
    let projectRoot = URL(filePath: FileManager.default.currentDirectoryPath)
    let url = projectRoot
        .appending(path: ".tmp/tests/voice-captioner-app-model-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
