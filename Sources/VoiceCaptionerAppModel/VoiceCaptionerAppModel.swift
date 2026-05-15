import Combine
import Foundation
import VoiceCaptionerCore

public enum TranscriptionWorkflowState: Equatable, Sendable {
    case idle
    case running(message: String)
    case completed(segmentCount: Int)
    case cancelled
    case failed(message: String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

public struct TranscriptExportArtifact: Equatable, Sendable, Identifiable {
    public var id: String { url.path }
    public var label: String
    public var url: URL
    public var exists: Bool

    public init(label: String, url: URL, exists: Bool) {
        self.label = label
        self.url = url
        self.exists = exists
    }
}

public protocol TranscriptionWorkflow: Sendable {
    func run(
        meeting: MeetingFolder,
        model: WhisperModel,
        whisperExecutableURL: URL,
        chunkDuration: TimeInterval
    ) async throws -> RollingTranscriptionResult
}

public struct LocalWhisperTranscriptionWorkflow: TranscriptionWorkflow {
    public init() {}

    public func run(
        meeting: MeetingFolder,
        model: WhisperModel,
        whisperExecutableURL: URL,
        chunkDuration: TimeInterval
    ) async throws -> RollingTranscriptionResult {
        let transcriber = WhisperProcessTranscriber(
            configuration: WhisperProcessConfiguration(executableURL: whisperExecutableURL)
        )
        let pipeline = RollingTranscriptionPipeline(transcriber: transcriber)
        return try await pipeline.run(meeting: meeting, model: model, chunkDuration: chunkDuration)
    }
}

@MainActor
public final class VoiceCaptionerAppModel: ObservableObject {
    @Published public var outputRoot: URL {
        didSet { refreshHistoryPreservingSelection() }
    }
    @Published public var meetingTitle: String
    @Published public var delaySeconds: TimeInterval
    @Published public var chunkDurationSeconds: TimeInterval
    @Published public private(set) var meetings: [MeetingFolder]
    @Published public var selectedMeetingID: String?
    @Published public private(set) var permissionStatus: PermissionStatus?
    @Published public private(set) var status: String
    @Published public private(set) var isRecording: Bool
    @Published public private(set) var activeMeeting: MeetingFolder?
    @Published public private(set) var captureResult: CaptureResult?
    @Published public private(set) var rollingPreview: [TranscriptSegment]
    @Published public private(set) var downloadedModels: [DownloadedWhisperModel]
    @Published public var selectedDownloadedModelPath: String?
    @Published public private(set) var manualModelURL: URL?
    @Published public private(set) var whisperExecutableURL: URL?
    @Published public private(set) var transcriptionState: TranscriptionWorkflowState

    private let store: MeetingStore
    private let provider: any AudioCaptureProvider
    private let modelRegistry: ModelRegistry
    private let transcriptionWorkflow: any TranscriptionWorkflow
    private var activeHandle: CaptureHandle?
    private var transcriptionTask: Task<Void, Never>?

    public init(
        outputRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "VoiceCaptionerMeetings", directoryHint: .isDirectory),
        meetingTitle: String = "Meeting",
        delaySeconds: TimeInterval = 30,
        chunkDurationSeconds: TimeInterval = 30,
        store: MeetingStore = MeetingStore(),
        provider: any AudioCaptureProvider = NativeMacCaptureProvider(captureGatePassed: true),
        modelsDirectory: URL = URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "Models", directoryHint: .isDirectory),
        transcriptionWorkflow: any TranscriptionWorkflow = LocalWhisperTranscriptionWorkflow()
    ) {
        self.outputRoot = outputRoot
        self.meetingTitle = meetingTitle
        self.delaySeconds = delaySeconds
        self.chunkDurationSeconds = chunkDurationSeconds
        self.store = store
        self.provider = provider
        self.modelRegistry = ModelRegistry(modelsDirectory: modelsDirectory)
        self.transcriptionWorkflow = transcriptionWorkflow
        self.meetings = []
        self.selectedMeetingID = nil
        self.permissionStatus = nil
        self.status = "Ready — local-only recording and transcription"
        self.isRecording = false
        self.activeMeeting = nil
        self.captureResult = nil
        self.rollingPreview = []
        self.downloadedModels = []
        self.selectedDownloadedModelPath = nil
        self.manualModelURL = nil
        self.whisperExecutableURL = nil
        self.transcriptionState = .idle
    }

    deinit {
        transcriptionTask?.cancel()
    }

    public var selectedMeeting: MeetingFolder? {
        meetings.first { $0.metadata.id == selectedMeetingID }
    }

    public var selectedWhisperModel: WhisperModel? {
        if let selectedDownloadedModelPath,
           let downloaded = downloadedModels.first(where: { $0.model.localPath.path == selectedDownloadedModelPath }) {
            return downloaded.model
        }
        guard let manualModelURL else { return nil }
        return WhisperModel(name: manualModelURL.deletingPathExtension().lastPathComponent, localPath: manualModelURL)
    }

    public var canStartRecording: Bool {
        !isRecording && !meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var canTranscribeSelectedMeeting: Bool {
        selectedMeeting != nil
            && selectedWhisperModel != nil
            && whisperExecutableURL != nil
            && !transcriptionState.isRunning
    }

    public func refreshAll() {
        refreshModels()
        refreshHistoryPreservingSelection()
    }

    public func refreshModels() {
        do {
            downloadedModels = try modelRegistry.downloadedModelEntries()
            if selectedDownloadedModelPath == nil, let recommended = downloadedModels.first {
                selectedDownloadedModelPath = recommended.model.localPath.path
            }
            status = downloadedModels.isEmpty
                ? "No downloaded Whisper models found; choose a local .bin/.gguf model."
                : "Loaded \(downloadedModels.count) local Whisper model(s)."
        } catch {
            downloadedModels = []
            status = "Model scan failed: \(error.localizedDescription)"
        }
    }

    public func refreshHistoryPreservingSelection() {
        let previousSelection = selectedMeetingID
        do {
            meetings = try store.scanMeetings(outputRoot: outputRoot)
            if let previousSelection, meetings.contains(where: { $0.metadata.id == previousSelection }) {
                selectedMeetingID = previousSelection
            } else {
                selectedMeetingID = meetings.first?.metadata.id
            }
            status = "Indexed \(meetings.count) local meeting folder(s)."
        } catch {
            status = "History error: \(error.localizedDescription)"
        }
    }

    public func refreshPermissions() async {
        do {
            permissionStatus = try await provider.requestPermissions()
        } catch {
            status = "Permission check failed: \(error.localizedDescription)"
        }
    }

    public func setOutputRoot(_ url: URL) {
        outputRoot = url
    }

    public func setWhisperExecutable(_ url: URL) {
        whisperExecutableURL = url
        status = "Using local Whisper executable: \(url.lastPathComponent)"
    }

    public func setManualModel(_ url: URL) {
        guard modelRegistry.validateManualModel(at: url) else {
            status = "Manual model must be an existing .bin or .gguf file."
            return
        }
        manualModelURL = url
        selectedDownloadedModelPath = nil
        status = "Using manual local model: \(url.lastPathComponent)"
    }

    public func useDownloadedModel(path: String?) {
        selectedDownloadedModelPath = path
        if path != nil { manualModelURL = nil }
    }

    public func startRecording() async {
        guard !isRecording else { return }
        do {
            let title = normalizedMeetingTitle()
            let meeting = try store.createMeeting(outputRoot: outputRoot, title: title, delaySeconds: delaySeconds)
            let handle = try await provider.start(session: CaptureSessionConfig(outputFolder: meeting))
            activeMeeting = meeting
            activeHandle = handle
            captureResult = nil
            rollingPreview = []
            transcriptionState = .idle
            isRecording = true
            selectedMeetingID = meeting.metadata.id
            status = "Recording \(meeting.metadata.title) locally…"
            refreshHistoryPreservingSelection()
        } catch {
            status = "Start failed: \(error.localizedDescription)"
        }
    }

    public func stopRecording() async {
        guard let handle = activeHandle else { return }
        do {
            status = "Finalizing local capture…"
            let result = try await provider.stop(handle)
            captureResult = result
            activeHandle = nil
            isRecording = false
            if var meeting = activeMeeting {
                meeting.metadata = try store.readMetadata(at: meeting.metadataURL)
                activeMeeting = meeting
                selectedMeetingID = meeting.metadata.id
                rollingPreview = previewSegments(from: result)
            }
            status = result.status == .complete
                ? "Capture complete: \(result.tracks.count) separated track(s). Ready for local transcription."
                : "Capture interrupted: \(result.failures.map(\.message).joined(separator: "; "))"
            refreshHistoryPreservingSelection()
        } catch {
            status = "Stop failed: \(error.localizedDescription)"
        }
    }

    public func beginTranscription() {
        guard transcriptionTask == nil || transcriptionState.isRunning == false else { return }
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            await self.transcribeSelectedMeeting()
        }
    }

    public func transcribeSelectedMeeting() async {
        guard let meeting = selectedMeeting else {
            status = "Select a meeting before transcription."
            return
        }
        guard let model = selectedWhisperModel else {
            status = "Choose a local Whisper model before transcription."
            return
        }
        guard let whisperExecutableURL else {
            status = "Choose a local whisper.cpp executable before transcription."
            return
        }

        transcriptionState = .running(message: "Chunking separated tracks and transcribing locally…")
        status = "Transcribing \(meeting.metadata.title) locally; no cloud processing."
        do {
            let result = try await transcriptionWorkflow.run(
                meeting: meeting,
                model: model,
                whisperExecutableURL: whisperExecutableURL,
                chunkDuration: chunkDurationSeconds
            )
            if Task.isCancelled {
                transcriptionState = .cancelled
                status = "Local transcription cancelled."
                return
            }
            rollingPreview = result.finalSegments
            transcriptionState = .completed(segmentCount: result.finalSegments.count)
            status = "Transcription complete: wrote Markdown, SRT, and JSON exports locally."
            refreshHistoryPreservingSelection()
        } catch is CancellationError {
            transcriptionState = .cancelled
            status = "Local transcription cancelled."
        } catch {
            transcriptionState = .failed(message: error.localizedDescription)
            status = "Transcription failed: \(error.localizedDescription)"
        }
        transcriptionTask = nil
    }

    public func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcriptionState = .cancelled
        status = "Local transcription cancellation requested."
    }

    public func regenerateChunkPlan() {
        guard let selectedMeeting else { return }
        do {
            let chunks = try AudioChunker.planChunks(for: selectedMeeting, chunkDuration: chunkDurationSeconds)
            try AudioChunker.writeManifest(chunks, to: selectedMeeting.chunksDirectory.appending(path: "chunks.json"))
            status = "Regenerated \(chunks.count) local chunk work item(s)."
        } catch {
            status = "Chunk plan failed: \(error.localizedDescription)"
        }
    }

    public func exportArtifacts(for meeting: MeetingFolder? = nil) -> [TranscriptExportArtifact] {
        guard let meeting = meeting ?? selectedMeeting else { return [] }
        let directory = meeting.transcriptDirectory
        let artifacts = [
            ("Markdown", directory.appending(path: "final.md", directoryHint: .notDirectory)),
            ("SRT", directory.appending(path: "final.srt", directoryHint: .notDirectory)),
            ("JSON", directory.appending(path: "final.json", directoryHint: .notDirectory))
        ]
        return artifacts.map { label, url in
            TranscriptExportArtifact(label: label, url: url, exists: FileManager.default.fileExists(atPath: url.path))
        }
    }

    private func normalizedMeetingTitle() -> String {
        let trimmed = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Meeting" : trimmed
    }

    private func previewSegments(from result: CaptureResult) -> [TranscriptSegment] {
        result.tracks.compactMap { track in
            guard let duration = track.duration else { return nil }
            return TranscriptSegment(
                id: "preview-\(track.kind.rawValue)",
                sourceTrack: track.kind,
                speakerLabel: track.kind == .microphone ? "Local" : "Remote",
                start: track.startOffset ?? 0,
                end: (track.startOffset ?? 0) + min(duration, delaySeconds),
                text: "Captured \(track.kind.rawValue) track; run local transcription to replace this draft.",
                isDraft: true
            )
        }
    }
}
