import Combine
import Foundation
import VoiceCaptionerCore

public enum EditableMarkdownSource: Equatable, Sendable {
  case empty
  case finalMarkdown
  case editedMarkdown
}

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

public enum EditableMarkdownSource: Equatable, Sendable {
  case none
  case finalMarkdown
  case editedMarkdown
  case empty
}

public enum EditableMarkdownSource: Equatable, Sendable {
  case empty
  case finalMarkdown
  case editedMarkdown

  public var filename: String? {
    switch self {
    case .empty: return nil
    case .finalMarkdown: return "final.md"
    case .editedMarkdown: return "edited.md"
    }
  }
}

public struct WhisperExecutableCandidate: Equatable, Sendable {
  public var url: URL
  public var source: String

  public init(url: URL, source: String) {
    self.url = url
    self.source = source
  }
}

public enum WhisperExecutableLocator {
  public static func bundledExecutable(bundle: Bundle = .main) -> WhisperExecutableCandidate? {
    let candidates = [
      bundle.url(forResource: "whisper-cli", withExtension: nil),
      bundle.url(forResource: "main", withExtension: nil),
      bundle.resourceURL?.appending(path: "whisper-cli", directoryHint: .notDirectory),
      bundle.resourceURL?.appending(path: "main", directoryHint: .notDirectory),
    ].compactMap { $0 }

    guard
      let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    else {
      return nil
    }
    return WhisperExecutableCandidate(url: url, source: "bundled")
  }

  public static func packageResourceExecutable(
    projectRoot: URL = URL(filePath: FileManager.default.currentDirectoryPath)
  ) -> WhisperExecutableCandidate? {
    let candidates = [
      projectRoot.appending(path: "Resources/whisper-cli", directoryHint: .notDirectory),
      projectRoot.appending(path: "Resources/main", directoryHint: .notDirectory),
      projectRoot.appending(path: ".build/debug/whisper-cli", directoryHint: .notDirectory),
      projectRoot.appending(path: ".build/release/whisper-cli", directoryHint: .notDirectory),
    ]
    guard
      let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    else {
      return nil
    }
    return WhisperExecutableCandidate(url: url, source: "project")
  }

  public static func firstAvailable(
    bundle: Bundle = .main,
    projectRoot: URL = URL(filePath: FileManager.default.currentDirectoryPath)
  ) -> WhisperExecutableCandidate? {
    bundledExecutable(bundle: bundle) ?? packageResourceExecutable(projectRoot: projectRoot)
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

public protocol LiveTranscriptionWorkflow: Sendable {
  func makePipeline(whisperExecutableURL: URL) -> LiveTranscriptionPipeline
}

public struct LocalWhisperTranscriptionWorkflow: TranscriptionWorkflow, LiveTranscriptionWorkflow {
  public init() {}

  public func run(
    meeting: MeetingFolder,
    model: WhisperModel,
    whisperExecutableURL: URL,
    chunkDuration: TimeInterval
  ) async throws -> RollingTranscriptionResult {
    let pipeline = RollingTranscriptionPipeline(
      transcriber: makeTranscriber(whisperExecutableURL: whisperExecutableURL))
    return try await pipeline.run(meeting: meeting, model: model, chunkDuration: chunkDuration)
  }

  public func makePipeline(whisperExecutableURL: URL) -> LiveTranscriptionPipeline {
    LiveTranscriptionPipeline(
      transcriber: makeTranscriber(whisperExecutableURL: whisperExecutableURL))
  }

  private func makeTranscriber(whisperExecutableURL: URL) -> WhisperProcessTranscriber {
    WhisperProcessTranscriber(
      configuration: WhisperProcessConfiguration(executableURL: whisperExecutableURL)
    )
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
  @Published public var language: AppLanguage {
    didSet {
      if oldValue != language {
        status = Self.statusText(.ready, language: language)
      }
    }
  }
  @Published public private(set) var meetings: [MeetingFolder]
  @Published public private(set) var selectedMeetingID: String?
  @Published public private(set) var permissionStatus: PermissionStatus?
  @Published public private(set) var status: String
  @Published public private(set) var isRecording: Bool
  @Published public private(set) var activeMeeting: MeetingFolder?
  @Published public private(set) var captureResult: CaptureResult?
  @Published public private(set) var rollingPreview: [TranscriptSegment]
  @Published public var editableMarkdownText: String
  @Published public private(set) var editableMarkdownSource: EditableMarkdownSource
  @Published public private(set) var editableMarkdownMeetingID: String?
  @Published public private(set) var isEditableMarkdownDirty: Bool
  @Published public private(set) var downloadedModels: [DownloadedWhisperModel]
  @Published public var selectedDownloadedModelPath: String?
  @Published public private(set) var manualModelURL: URL?
  @Published public private(set) var whisperExecutableURL: URL?
  @Published public private(set) var whisperExecutableSource: String?
  @Published public private(set) var transcriptionState: TranscriptionWorkflowState
  @Published public private(set) var editableMarkdownText: String
  @Published public private(set) var editableMarkdownSource: EditableMarkdownSource
  @Published public private(set) var editableMarkdownMeetingID: String?
  @Published public private(set) var isEditableMarkdownDirty: Bool
  @Published public private(set) var editableMarkdownStatus: String?

  public static let finalMarkdownFilename = "final.md"
  public static let editedMarkdownFilename = "edited.md"

  private let store: MeetingStore
  private let provider: any AudioCaptureProvider
  private let modelRegistry: ModelRegistry
  private let transcriptionWorkflow: any TranscriptionWorkflow
  private let liveTranscriptionWorkflow: (any LiveTranscriptionWorkflow)?
  private var activeHandle: CaptureHandle?
  private var transcriptionTask: Task<Void, Never>?
  private var liveTranscriptionTask: Task<Void, Never>?
  private var liveTranscriptionPipeline: LiveTranscriptionPipeline?

  public static let finalMarkdownFilename = "final.md"
  public static let editedMarkdownFilename = "edited.md"

  public static func defaultModelsDirectory(bundle: Bundle = .main) -> URL {
    let bundledModels = bundle.resourceURL?.appending(path: "Models", directoryHint: .isDirectory)
    if let bundledModels, FileManager.default.fileExists(atPath: bundledModels.path) {
      return bundledModels
    }
    return URL(filePath: FileManager.default.currentDirectoryPath)
      .appending(path: "Models", directoryHint: .isDirectory)
  }

  public init(
    outputRoot: URL = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "VoiceCaptionerMeetings", directoryHint: .isDirectory),
    meetingTitle: String = "会议",
    language: AppLanguage = .zhHans,
    delaySeconds: TimeInterval = 30,
    chunkDurationSeconds: TimeInterval = 30,
    store: MeetingStore = MeetingStore(),
    provider: any AudioCaptureProvider = NativeMacCaptureProvider(captureGatePassed: true),
    modelsDirectory: URL = VoiceCaptionerAppModel.defaultModelsDirectory(),
    transcriptionWorkflow: any TranscriptionWorkflow = LocalWhisperTranscriptionWorkflow(),
    liveTranscriptionWorkflow: (any LiveTranscriptionWorkflow)? =
      LocalWhisperTranscriptionWorkflow(),
    defaultWhisperExecutable: WhisperExecutableCandidate? =
      WhisperExecutableLocator.firstAvailable()
  ) {
    self.outputRoot = outputRoot
    self.meetingTitle = meetingTitle
    self.language = language
    self.delaySeconds = delaySeconds
    self.chunkDurationSeconds = chunkDurationSeconds
    self.store = store
    self.provider = provider
    self.modelRegistry = ModelRegistry(modelsDirectory: modelsDirectory)
    self.transcriptionWorkflow = transcriptionWorkflow
    self.liveTranscriptionWorkflow = liveTranscriptionWorkflow
    self.meetings = []
    self.selectedMeetingID = nil
    self.permissionStatus = nil
    self.status = Self.statusText(.ready, language: language)
    self.isRecording = false
    self.activeMeeting = nil
    self.captureResult = nil
    self.rollingPreview = []
    self.editableMarkdownText = ""
    self.editableMarkdownSource = .none
    self.editableMarkdownMeetingID = nil
    self.isEditableMarkdownDirty = false
    self.downloadedModels = []
    self.selectedDownloadedModelPath = nil
    self.manualModelURL = nil
    self.whisperExecutableURL = defaultWhisperExecutable?.url
    self.whisperExecutableSource = defaultWhisperExecutable?.source
    self.transcriptionState = .idle
    self.editableMarkdownText = ""
    self.editableMarkdownSource = .empty
    self.editableMarkdownMeetingID = nil
    self.isEditableMarkdownDirty = false
    self.editableMarkdownStatus = nil
  }

  deinit {
    transcriptionTask?.cancel()
    liveTranscriptionTask?.cancel()
  }

  public static let finalMarkdownFilename = "final.md"
  public static let editedMarkdownFilename = "edited.md"

  public var strings: AppStrings { AppStrings(language: language) }

  public func setLanguage(_ language: AppLanguage) {
    self.language = language
  }

  public var selectedMeeting: MeetingFolder? {
    meeting(withID: selectedMeetingID)
  }

  public var canSaveEditableMarkdown: Bool {
    editableMarkdownMeetingID != nil
  }

  private func meeting(withID id: String?) -> MeetingFolder? {
    guard let id else { return nil }
    return meetings.first { $0.metadata.id == id }
  }

  public var selectedWhisperModel: WhisperModel? {
    if let selectedDownloadedModelPath,
      let downloaded = downloadedModels.first(where: {
        $0.model.localPath.path == selectedDownloadedModelPath
      })
    {
      return downloaded.model
    }
    guard let manualModelURL else { return nil }
    return WhisperModel(
      name: manualModelURL.deletingPathExtension().lastPathComponent, localPath: manualModelURL)
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

  public var canSaveEditableMarkdown: Bool {
    editableMarkdownMeetingID != nil && isEditableMarkdownDirty
  }

  public func editedMarkdownURL(for meeting: MeetingFolder) -> URL {
    meeting.transcriptDirectory.appending(
      path: Self.editedMarkdownFilename, directoryHint: .notDirectory)
  }

  public func finalMarkdownURL(for meeting: MeetingFolder) -> URL {
    meeting.transcriptDirectory.appending(
      path: Self.finalMarkdownFilename, directoryHint: .notDirectory)
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
      let needsExecutable = whisperExecutableURL == nil
      status =
        downloadedModels.isEmpty
        ? statusText(.noDownloadedModels(needsExecutable: needsExecutable))
        : statusText(.loadedModels(count: downloadedModels.count, needsExecutable: needsExecutable))
    } catch {
      downloadedModels = []
      status = statusText(.modelScanFailed(error.localizedDescription))
    }
  }

  public func refreshHistoryPreservingSelection() {
    autosaveEditableMarkdownIfDirty()
    let previousSelection = selectedMeetingID
    autosaveEditableMarkdownIfDirty()
    do {
      meetings = try store.scanMeetings(outputRoot: outputRoot)
      let nextSelection: String?
      if let previousSelection, meetings.contains(where: { $0.metadata.id == previousSelection }) {
        nextSelection = previousSelection
      } else {
        nextSelection = meetings.first?.metadata.id
      }
      selectedMeetingID = nextSelection
      loadEditableMarkdown(for: meeting(withID: nextSelection))
      status = statusText(.indexedMeetings(count: meetings.count))
    } catch {
      status = statusText(.historyError(error.localizedDescription))
    }
  }

  public func selectMeeting(id: String?) {
    guard id != selectedMeetingID else { return }
    autosaveEditableMarkdownIfDirty()
    selectedMeetingID = id
    loadEditableMarkdown(for: meeting(withID: id))
  }

  public func refreshPermissions() async {
    do {
      permissionStatus = try await provider.requestPermissions()
    } catch {
      status = statusText(.permissionCheckFailed(error.localizedDescription))
    }
  }

  public func setOutputRoot(_ url: URL) {
    autosaveEditableMarkdownIfDirty()
    outputRoot = url
  }

  public func setWhisperExecutable(_ url: URL) {
    whisperExecutableURL = url
    whisperExecutableSource = "manual"
    status = statusText(.usingManualExecutable(url.lastPathComponent))
  }

  public func useDefaultWhisperExecutable() {
    if let candidate = WhisperExecutableLocator.firstAvailable() {
      whisperExecutableURL = candidate.url
      whisperExecutableSource = candidate.source
      status = statusText(
        .usingExecutable(source: candidate.source, name: candidate.url.lastPathComponent))
    } else {
      whisperExecutableURL = nil
      whisperExecutableSource = nil
      status = statusText(.noBundledExecutable)
    }
  }

  public func setManualModel(_ url: URL) {
    guard modelRegistry.validateManualModel(at: url) else {
      status = statusText(.invalidManualModel)
      return
    }
    manualModelURL = url
    selectedDownloadedModelPath = nil
    status = statusText(.usingManualModel(url.lastPathComponent))
  }

  public func useDownloadedModel(path: String?) {
    selectedDownloadedModelPath = path
    if path != nil { manualModelURL = nil }
  }

  public func startRecording() async {
    guard !isRecording else { return }
    do {
      let title = normalizedMeetingTitle()
      let meeting = try store.createMeeting(
        outputRoot: outputRoot, title: title, delaySeconds: delaySeconds)
      let handle = try await provider.start(session: CaptureSessionConfig(outputFolder: meeting))
      activeMeeting = meeting
      activeHandle = handle
      captureResult = nil
      rollingPreview = []
      transcriptionState = .idle
      isRecording = true
      selectMeeting(id: meeting.metadata.id)
      status = statusText(.recording(meeting.metadata.title))
      startLiveTranscriptionIfPossible(for: meeting)
      refreshHistoryPreservingSelection()
    } catch {
      status = statusText(.startFailed(error.localizedDescription))
    }
  }

  public func stopRecording() async {
    guard let handle = activeHandle else { return }
    do {
      liveTranscriptionTask?.cancel()
      liveTranscriptionTask = nil
      status = statusText(.finalizingCapture)
      let result = try await provider.stop(handle)
      captureResult = result
      activeHandle = nil
      isRecording = false
      if var meeting = activeMeeting {
        meeting.metadata = try store.readMetadata(at: meeting.metadataURL)
        activeMeeting = meeting
        selectMeeting(id: meeting.metadata.id)
        if rollingPreview.isEmpty {
          rollingPreview = previewSegments(from: result)
        }
      }
      status =
        result.status == .complete
        ? statusText(.captureComplete(trackCount: result.tracks.count))
        : statusText(.captureInterrupted(result.failures.map(\.message).joined(separator: "; ")))
      refreshHistoryPreservingSelection()
    } catch {
      status = statusText(.stopFailed(error.localizedDescription))
    }
  }

  private func startLiveTranscriptionIfPossible(for meeting: MeetingFolder) {
    guard liveTranscriptionTask == nil else { return }
    guard let model = selectedWhisperModel, let whisperExecutableURL, let liveTranscriptionWorkflow
    else {
      status = statusText(.recordingWithoutLiveTranscription(meeting.metadata.title))
      return
    }
    let pipeline = liveTranscriptionWorkflow.makePipeline(
      whisperExecutableURL: whisperExecutableURL)
    liveTranscriptionPipeline = pipeline
    let chunkDuration = max(5, chunkDurationSeconds)
    let pollInterval = max(0.1, min(2, min(delaySeconds, chunkDuration) / 2))
    liveTranscriptionTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        guard !Task.isCancelled else { return }
        await self.pollLiveTranscription(
          meeting: meeting, model: model, pipeline: pipeline, chunkDuration: chunkDuration)
      }
    }
  }

  private func pollLiveTranscription(
    meeting: MeetingFolder,
    model: WhisperModel,
    pipeline: LiveTranscriptionPipeline,
    chunkDuration: TimeInterval
  ) async {
    do {
      let update = try await pipeline.poll(
        meeting: meeting, model: model, chunkDuration: chunkDuration)
      if !update.draftSegments.isEmpty {
        rollingPreview = update.draftSegments
        status = statusText(.liveTranscriptionUpdated(segmentCount: update.draftSegments.count))
      }
    } catch {
      status = statusText(.liveTranscriptionFailed(error.localizedDescription))
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
    autosaveEditableMarkdownIfDirty()
    guard let meeting = selectedMeeting else {
      status = statusText(.selectMeetingBeforeTranscription)
      return
    }
    guard let model = selectedWhisperModel else {
      status = statusText(.chooseModelBeforeTranscription)
      return
    }
    guard let whisperExecutableURL else {
      status = statusText(.chooseExecutableBeforeTranscription)
      return
    }

    autosaveEditableMarkdownIfDirty()
    transcriptionState = .running(message: statusText(.chunkingAndTranscribing))
    status = statusText(.transcribing(meeting.metadata.title))
    autosaveEditableMarkdownIfDirty()
    do {
      let result = try await transcriptionWorkflow.run(
        meeting: meeting,
        model: model,
        whisperExecutableURL: whisperExecutableURL,
        chunkDuration: chunkDurationSeconds
      )
      if Task.isCancelled {
        transcriptionState = .cancelled
        status = statusText(.localTranscriptionCancelled)
        return
      }
      rollingPreview = result.finalSegments
      transcriptionState = .completed(segmentCount: result.finalSegments.count)
      status = statusText(.transcriptionComplete)
      refreshHistoryPreservingSelection()
      loadEditableMarkdown(for: selectedMeeting)
      loadEditableMarkdown(for: selectedMeeting)
    } catch is CancellationError {
      transcriptionState = .cancelled
      status = statusText(.localTranscriptionCancelled)
    } catch {
      transcriptionState = .failed(message: error.localizedDescription)
      status = statusText(.transcriptionFailed(error.localizedDescription))
    }
    transcriptionTask = nil
  }

  public func cancelTranscription() {
    transcriptionTask?.cancel()
    transcriptionTask = nil
    transcriptionState = .cancelled
    status = statusText(.transcriptionCancellationRequested)
  }

  public func regenerateChunkPlan() {
    guard let selectedMeeting else { return }
    do {
      let chunks = try AudioChunker.planChunks(
        for: selectedMeeting, chunkDuration: chunkDurationSeconds)
      try AudioChunker.writeManifest(
        chunks, to: selectedMeeting.chunksDirectory.appending(path: "chunks.json"))
      status = statusText(.regeneratedChunks(count: chunks.count))
    } catch {
      status = statusText(.chunkPlanFailed(error.localizedDescription))
    }
  }


  public func selectMeeting(id: String?) {
    if selectedMeetingID == id, editableMarkdownMeetingID == id { return }
    autosaveEditableMarkdownIfDirty()
    selectedMeetingID = id
    loadEditableMarkdown(for: selectedMeeting)
  }

  public func finalMarkdownURL(for meeting: MeetingFolder) -> URL {
    meeting.transcriptDirectory.appending(path: Self.finalMarkdownFilename, directoryHint: .notDirectory)
  }

  public func editedMarkdownURL(for meeting: MeetingFolder) -> URL {
    meeting.transcriptDirectory.appending(path: Self.editedMarkdownFilename, directoryHint: .notDirectory)
  }

  public func loadEditableMarkdown(for meeting: MeetingFolder?) {
    editableMarkdownMeetingID = meeting?.metadata.id
    editableMarkdownStatus = nil
    guard let meeting else {
      editableMarkdownText = ""
      editableMarkdownSource = .empty
      isEditableMarkdownDirty = false
      return
    }

    let editedURL = editedMarkdownURL(for: meeting)
    let finalURL = finalMarkdownURL(for: meeting)
    do {
      if FileManager.default.fileExists(atPath: editedURL.path) {
        editableMarkdownText = try String(contentsOf: editedURL, encoding: .utf8)
        editableMarkdownSource = .editedMarkdown
      } else if FileManager.default.fileExists(atPath: finalURL.path) {
        editableMarkdownText = try String(contentsOf: finalURL, encoding: .utf8)
        editableMarkdownSource = .finalMarkdown
      } else {
        editableMarkdownText = ""
        editableMarkdownSource = .empty
      }
      isEditableMarkdownDirty = false
    } catch {
      editableMarkdownText = ""
      editableMarkdownSource = .empty
      isEditableMarkdownDirty = false
      editableMarkdownStatus = statusText(.editableMarkdownLoadFailed(error.localizedDescription))
      status = editableMarkdownStatus ?? status
    }
  }

  public func updateEditableMarkdownText(_ text: String) {
    if editableMarkdownText != text {
      editableMarkdownText = text
      isEditableMarkdownDirty = true
      editableMarkdownStatus = nil
    }
  }

  public func saveEditableMarkdown() {
    guard let meetingID = editableMarkdownMeetingID, let meeting = meeting(for: meetingID) else { return }
    do {
      try FileManager.default.createDirectory(
        at: meeting.transcriptDirectory, withIntermediateDirectories: true)
      try editableMarkdownText.write(
        to: editedMarkdownURL(for: meeting), atomically: true, encoding: .utf8)
      editableMarkdownSource = .editedMarkdown
      isEditableMarkdownDirty = false
      editableMarkdownStatus = statusText(.editableMarkdownSaved)
    } catch {
      editableMarkdownStatus = statusText(.editableMarkdownSaveFailed(error.localizedDescription))
      status = editableMarkdownStatus ?? status
    }
  }

  public func autosaveEditableMarkdownIfDirty() {
    guard isEditableMarkdownDirty else { return }
    saveEditableMarkdown()
  }

  private func meeting(for id: String) -> MeetingFolder? {
    if let meeting = meetings.first(where: { $0.metadata.id == id }) { return meeting }
    if activeMeeting?.metadata.id == id { return activeMeeting }
    return nil
  }

  public func exportArtifacts(for meeting: MeetingFolder? = nil) -> [TranscriptExportArtifact] {
    guard let meeting = meeting ?? selectedMeeting else { return [] }
    let directory = meeting.transcriptDirectory
    let artifacts = [
      ("Machine Markdown", finalMarkdownURL(for: meeting)),
      ("SRT", directory.appending(path: "final.srt", directoryHint: .notDirectory)),
      ("JSON", directory.appending(path: "final.json", directoryHint: .notDirectory)),
      ("Edited Markdown", editedMarkdownURL(for: meeting)),
    ]
    return artifacts.map { label, url in
      TranscriptExportArtifact(
        label: label, url: url, exists: FileManager.default.fileExists(atPath: url.path))
    }
  }

  public func loadEditableMarkdown(for meeting: MeetingFolder?) {
    guard let meeting else {
      editableMarkdownText = ""
      editableMarkdownSource = .none
      editableMarkdownMeetingID = nil
      isEditableMarkdownDirty = false
      return
    }

    let editedURL = editedMarkdownURL(for: meeting)
    let finalURL = finalMarkdownURL(for: meeting)
    do {
      if FileManager.default.fileExists(atPath: editedURL.path) {
        editableMarkdownText = try String(contentsOf: editedURL, encoding: .utf8)
        editableMarkdownSource = .editedMarkdown
      } else if FileManager.default.fileExists(atPath: finalURL.path) {
        editableMarkdownText = try String(contentsOf: finalURL, encoding: .utf8)
        editableMarkdownSource = .finalMarkdown
      } else {
        editableMarkdownText = ""
        editableMarkdownSource = .none
      }
      editableMarkdownMeetingID = meeting.metadata.id
      isEditableMarkdownDirty = false
    } catch {
      editableMarkdownText = ""
      editableMarkdownSource = .none
      editableMarkdownMeetingID = meeting.metadata.id
      isEditableMarkdownDirty = false
      status = statusText(.markdownReadFailed(error.localizedDescription))
    }
  }

  public func updateEditableMarkdownText(_ text: String) {
    guard text != editableMarkdownText else { return }
    editableMarkdownText = text
    isEditableMarkdownDirty = true
  }

  public func saveEditableMarkdown() {
    guard
      let meetingID = editableMarkdownMeetingID,
      let meeting = meetings.first(where: { $0.metadata.id == meetingID })
    else {
      status = statusText(.editableMarkdownNoMeeting)
      return
    }
    do {
      try FileManager.default.createDirectory(
        at: meeting.transcriptDirectory, withIntermediateDirectories: true)
      try editableMarkdownText.write(
        to: editedMarkdownURL(for: meeting), atomically: true, encoding: .utf8)
      editableMarkdownSource = .editedMarkdown
      isEditableMarkdownDirty = false
      status = statusText(.editableMarkdownSaved)
    } catch {
      status = statusText(.editableMarkdownSaveFailed(error.localizedDescription))
    }
  }

  public func autosaveEditableMarkdownIfDirty() {
    guard isEditableMarkdownDirty else { return }
    saveEditableMarkdown()
  }

  private enum AppStatusMessage {
    case ready
    case noDownloadedModels(needsExecutable: Bool)
    case loadedModels(count: Int, needsExecutable: Bool)
    case modelScanFailed(String)
    case indexedMeetings(count: Int)
    case historyError(String)
    case permissionCheckFailed(String)
    case usingManualExecutable(String)
    case usingExecutable(source: String, name: String)
    case noBundledExecutable
    case invalidManualModel
    case usingManualModel(String)
    case recording(String)
    case startFailed(String)
    case finalizingCapture
    case captureComplete(trackCount: Int)
    case captureInterrupted(String)
    case stopFailed(String)
    case selectMeetingBeforeTranscription
    case chooseModelBeforeTranscription
    case chooseExecutableBeforeTranscription
    case chunkingAndTranscribing
    case transcribing(String)
    case localTranscriptionCancelled
    case transcriptionComplete
    case transcriptionFailed(String)
    case transcriptionCancellationRequested
    case regeneratedChunks(count: Int)
    case chunkPlanFailed(String)
    case capturedTrackPreview(String)
    case recordingWithoutLiveTranscription(String)
    case liveTranscriptionUpdated(segmentCount: Int)
    case liveTranscriptionFailed(String)
    case editableMarkdownSaved
    case editableMarkdownNoMeeting
    case editableMarkdownSaveFailed(String)
    case markdownReadFailed(String)
  }

  private func statusText(_ message: AppStatusMessage) -> String {
    Self.statusText(message, language: language)
  }

  private static func statusText(_ message: AppStatusMessage, language: AppLanguage) -> String {
    let executableHint: String
    switch language {
    case .zhHans: executableHint = " 请使用内置或手动选择 whisper.cpp 可执行文件。"
    case .en: executableHint = " Choose a bundled or manual whisper.cpp executable."
    case .de: executableHint = " Integriertes oder manuelles whisper.cpp-Programm auswählen."
    }

    func sourceLabel(_ source: String) -> String {
      switch (language, source) {
      case (.zhHans, "bundled"): return "内置"
      case (.zhHans, "project"): return "项目"
      case (.zhHans, _): return "手动"
      case (.en, "bundled"): return "bundled"
      case (.en, "project"): return "project"
      case (.en, _): return "manual"
      case (.de, "bundled"): return "integriertes"
      case (.de, "project"): return "Projekt"
      case (.de, _): return "manuelles"
      }
    }

    switch (language, message) {
    case (.zhHans, .ready): return "就绪 — 本地录音与转写"
    case (.zhHans, .noDownloadedModels(let needsExecutable)):
      return "未找到已下载的 Whisper 模型；请选择本地 .bin/.gguf 模型。" + (needsExecutable ? executableHint : "")
    case (.zhHans, .loadedModels(let count, let needsExecutable)):
      return "已加载 \(count) 个本地 Whisper 模型。" + (needsExecutable ? executableHint : "")
    case (.zhHans, .modelScanFailed(let error)): return "模型扫描失败：\(error)"
    case (.zhHans, .indexedMeetings(let count)): return "已索引 \(count) 个本地会议文件夹。"
    case (.zhHans, .historyError(let error)): return "历史记录错误：\(error)"
    case (.zhHans, .permissionCheckFailed(let error)): return "权限检查失败：\(error)"
    case (.zhHans, .usingManualExecutable(let name)): return "正在使用手动选择的本地 Whisper 可执行文件：\(name)"
    case (.zhHans, .usingExecutable(let source, let name)):
      return "正在使用\(sourceLabel(source)) Whisper 可执行文件：\(name)"
    case (.zhHans, .noBundledExecutable): return "未找到内置 whisper.cpp 可执行文件；请手动选择。"
    case (.zhHans, .invalidManualModel): return "手动模型必须是存在的 .bin 或 .gguf 文件。"
    case (.zhHans, .usingManualModel(let name)): return "正在使用手动选择的本地模型：\(name)"
    case (.zhHans, .recording(let title)): return "正在本地录制“\(title)”…"
    case (.zhHans, .startFailed(let error)): return "启动失败：\(error)"
    case (.zhHans, .finalizingCapture): return "正在完成本地录音…"
    case (.zhHans, .captureComplete(let trackCount)): return "录音完成：已分离 \(trackCount) 条音轨。可以进行本地转写。"
    case (.zhHans, .captureInterrupted(let message)): return "录音中断：\(message)"
    case (.zhHans, .stopFailed(let error)): return "停止失败：\(error)"
    case (.zhHans, .selectMeetingBeforeTranscription): return "请先选择会议再转写。"
    case (.zhHans, .chooseModelBeforeTranscription): return "转写前请选择本地 Whisper 模型。"
    case (.zhHans, .chooseExecutableBeforeTranscription): return "转写前请选择本地 whisper.cpp 可执行文件。"
    case (.zhHans, .chunkingAndTranscribing): return "正在分块音轨并在本地转写…"
    case (.zhHans, .transcribing(let title)): return "正在本地转写“\(title)”；不会上传云端。"
    case (.zhHans, .localTranscriptionCancelled): return "本地转写已取消。"
    case (.zhHans, .transcriptionComplete): return "转写完成：已在本地写入 Markdown、SRT 和 JSON 导出。"
    case (.zhHans, .transcriptionFailed(let error)): return "转写失败：\(error)"
    case (.zhHans, .transcriptionCancellationRequested): return "已请求取消本地转写。"
    case (.zhHans, .regeneratedChunks(let count)): return "已重新生成 \(count) 个本地分块任务。"
    case (.zhHans, .chunkPlanFailed(let error)): return "分块计划失败：\(error)"
    case (.zhHans, .capturedTrackPreview(let track)): return "已捕获\(track)音轨；运行本地转写后会替换此草稿。"
    case (.zhHans, .recordingWithoutLiveTranscription(let title)):
      return "正在本地录制“\(title)”；选择本地模型和 whisper.cpp 后可启用延迟实时转写。"
    case (.zhHans, .liveTranscriptionUpdated(let count)): return "延迟实时转写已更新：\(count) 个草稿片段。"
    case (.zhHans, .liveTranscriptionFailed(let error)): return "延迟实时转写失败：\(error)"
    case (.zhHans, .editableMarkdownSaved): return "用户编辑版 Markdown 已保存。"
    case (.zhHans, .editableMarkdownNoMeeting): return "没有可保存的已加载会议。"
    case (.zhHans, .editableMarkdownSaveFailed(let error)): return "保存用户编辑版 Markdown 失败：\(error)"
    case (.zhHans, .markdownReadFailed(let error)): return "读取 Markdown 失败：\(error)"

    case (.en, .ready): return "Ready — local-only recording and transcription"
    case (.en, .noDownloadedModels(let needsExecutable)):
      return "No downloaded Whisper models found; choose a local .bin/.gguf model."
        + (needsExecutable ? executableHint : "")
    case (.en, .loadedModels(let count, let needsExecutable)):
      return "Loaded \(count) local Whisper model(s)." + (needsExecutable ? executableHint : "")
    case (.en, .modelScanFailed(let error)): return "Model scan failed: \(error)"
    case (.en, .indexedMeetings(let count)): return "Indexed \(count) local meeting folder(s)."
    case (.en, .historyError(let error)): return "History error: \(error)"
    case (.en, .permissionCheckFailed(let error)): return "Permission check failed: \(error)"
    case (.en, .usingManualExecutable(let name)):
      return "Using manual local Whisper executable: \(name)"
    case (.en, .usingExecutable(let source, let name)):
      return "Using \(sourceLabel(source)) Whisper executable: \(name)"
    case (.en, .noBundledExecutable):
      return "No bundled whisper.cpp executable found; choose one manually."
    case (.en, .invalidManualModel): return "Manual model must be an existing .bin or .gguf file."
    case (.en, .usingManualModel(let name)): return "Using manual local model: \(name)"
    case (.en, .recording(let title)): return "Recording \(title) locally…"
    case (.en, .startFailed(let error)): return "Start failed: \(error)"
    case (.en, .finalizingCapture): return "Finalizing local capture…"
    case (.en, .captureComplete(let trackCount)):
      return "Capture complete: \(trackCount) separated track(s). Ready for local transcription."
    case (.en, .captureInterrupted(let message)): return "Capture interrupted: \(message)"
    case (.en, .stopFailed(let error)): return "Stop failed: \(error)"
    case (.en, .selectMeetingBeforeTranscription): return "Select a meeting before transcription."
    case (.en, .chooseModelBeforeTranscription):
      return "Choose a local Whisper model before transcription."
    case (.en, .chooseExecutableBeforeTranscription):
      return "Choose a local whisper.cpp executable before transcription."
    case (.en, .chunkingAndTranscribing):
      return "Chunking separated tracks and transcribing locally…"
    case (.en, .transcribing(let title)):
      return "Transcribing \(title) locally; no cloud processing."
    case (.en, .localTranscriptionCancelled): return "Local transcription cancelled."
    case (.en, .transcriptionComplete):
      return "Transcription complete: wrote Markdown, SRT, and JSON exports locally."
    case (.en, .transcriptionFailed(let error)): return "Transcription failed: \(error)"
    case (.en, .transcriptionCancellationRequested):
      return "Local transcription cancellation requested."
    case (.en, .regeneratedChunks(let count)):
      return "Regenerated \(count) local chunk work item(s)."
    case (.en, .chunkPlanFailed(let error)): return "Chunk plan failed: \(error)"
    case (.en, .capturedTrackPreview(let track)):
      return "Captured \(track) track; run local transcription to replace this draft."
    case (.en, .recordingWithoutLiveTranscription(let title)):
      return
        "Recording \(title) locally; choose a local model and whisper.cpp executable to enable delayed live transcription."
    case (.en, .liveTranscriptionUpdated(let count)):
      return "Delayed live transcription updated: \(count) draft segment(s)."
    case (.en, .liveTranscriptionFailed(let error)): return "Delayed live transcription failed: \(error)"
    case (.en, .editableMarkdownSaved): return "Edited Markdown saved."
    case (.en, .editableMarkdownNoMeeting): return "No loaded meeting to save."
    case (.en, .editableMarkdownSaveFailed(let error)): return "Edited Markdown save failed: \(error)"
    case (.en, .markdownReadFailed(let error)): return "Markdown read failed: \(error)"

    case (.de, .ready): return "Bereit — lokale Aufnahme und Transkription"
    case (.de, .noDownloadedModels(let needsExecutable)):
      return
        "Keine heruntergeladenen Whisper-Modelle gefunden; lokales .bin/.gguf-Modell auswählen."
        + (needsExecutable ? executableHint : "")
    case (.de, .loadedModels(let count, let needsExecutable)):
      return "\(count) lokale Whisper-Modell(e) geladen." + (needsExecutable ? executableHint : "")
    case (.de, .modelScanFailed(let error)): return "Modellscan fehlgeschlagen: \(error)"
    case (.de, .indexedMeetings(let count)): return "\(count) lokale Besprechungsordner indiziert."
    case (.de, .historyError(let error)): return "Verlaufsfehler: \(error)"
    case (.de, .permissionCheckFailed(let error)):
      return "Berechtigungsprüfung fehlgeschlagen: \(error)"
    case (.de, .usingManualExecutable(let name)):
      return "Manuelles lokales Whisper-Programm wird verwendet: \(name)"
    case (.de, .usingExecutable(let source, let name)):
      return "\(sourceLabel(source)) Whisper-Programm wird verwendet: \(name)"
    case (.de, .noBundledExecutable):
      return "Kein integriertes whisper.cpp-Programm gefunden; bitte manuell auswählen."
    case (.de, .invalidManualModel):
      return "Das manuelle Modell muss eine vorhandene .bin- oder .gguf-Datei sein."
    case (.de, .usingManualModel(let name)):
      return "Manuelles lokales Modell wird verwendet: \(name)"
    case (.de, .recording(let title)): return "\(title) wird lokal aufgenommen…"
    case (.de, .startFailed(let error)): return "Start fehlgeschlagen: \(error)"
    case (.de, .finalizingCapture): return "Lokale Aufnahme wird abgeschlossen…"
    case (.de, .captureComplete(let trackCount)):
      return
        "Aufnahme abgeschlossen: \(trackCount) getrennte Spur(en). Bereit für lokale Transkription."
    case (.de, .captureInterrupted(let message)): return "Aufnahme unterbrochen: \(message)"
    case (.de, .stopFailed(let error)): return "Stopp fehlgeschlagen: \(error)"
    case (.de, .selectMeetingBeforeTranscription):
      return "Vor der Transkription eine Besprechung auswählen."
    case (.de, .chooseModelBeforeTranscription):
      return "Vor der Transkription ein lokales Whisper-Modell auswählen."
    case (.de, .chooseExecutableBeforeTranscription):
      return "Vor der Transkription ein lokales whisper.cpp-Programm auswählen."
    case (.de, .chunkingAndTranscribing):
      return "Getrennte Spuren werden in Chunks geteilt und lokal transkribiert…"
    case (.de, .transcribing(let title)):
      return "\(title) wird lokal transkribiert; keine Cloud-Verarbeitung."
    case (.de, .localTranscriptionCancelled): return "Lokale Transkription abgebrochen."
    case (.de, .transcriptionComplete):
      return "Transkription abgeschlossen: Markdown-, SRT- und JSON-Exporte lokal geschrieben."
    case (.de, .transcriptionFailed(let error)): return "Transkription fehlgeschlagen: \(error)"
    case (.de, .transcriptionCancellationRequested):
      return "Abbruch der lokalen Transkription angefordert."
    case (.de, .regeneratedChunks(let count)):
      return "\(count) lokale Chunk-Aufgabe(n) neu erzeugt."
    case (.de, .chunkPlanFailed(let error)): return "Chunk-Plan fehlgeschlagen: \(error)"
    case (.de, .capturedTrackPreview(let track)):
      return "\(track)-Spur erfasst; lokale Transkription ersetzt diesen Entwurf."
    case (.de, .recordingWithoutLiveTranscription(let title)):
      return
        "\(title) wird lokal aufgenommen; lokales Modell und whisper.cpp-Programm für verzögerte Live-Transkription auswählen."
    case (.de, .liveTranscriptionUpdated(let count)):
      return "Verzögerte Live-Transkription aktualisiert: \(count) Entwurfssegment(e)."
    case (.de, .liveTranscriptionFailed(let error)):
      return "Verzögerte Live-Transkription fehlgeschlagen: \(error)"
    case (.de, .editableMarkdownSaved): return "Bearbeitete Markdown-Datei gespeichert."
    case (.de, .editableMarkdownNoMeeting): return "Keine geladene Besprechung zum Speichern."
    case (.de, .editableMarkdownSaveFailed(let error)):
      return "Speichern der bearbeiteten Markdown-Datei fehlgeschlagen: \(error)"
    case (.de, .markdownReadFailed(let error)): return "Markdown konnte nicht gelesen werden: \(error)"
    }
  }

  private func meeting(withID id: String?) -> MeetingFolder? {
    guard let id else { return nil }
    if let meeting = meetings.first(where: { $0.metadata.id == id }) {
      return meeting
    }
    if activeMeeting?.metadata.id == id {
      return activeMeeting
    }
    return nil
  }

  private func speakerLabel(for kind: AudioTrackKind) -> String {
    switch (language, kind) {
    case (.zhHans, .microphone): return "本地"
    case (.zhHans, .system), (.zhHans, .mixed): return "远端"
    case (.en, .microphone): return "Local"
    case (.en, .system), (.en, .mixed): return "Remote"
    case (.de, .microphone): return "Lokal"
    case (.de, .system), (.de, .mixed): return "Remote"
    }
  }

  private func trackName(for kind: AudioTrackKind) -> String {
    switch (language, kind) {
    case (.zhHans, .system): return "系统音频"
    case (.zhHans, .microphone): return "麦克风"
    case (.zhHans, .mixed): return "混合"
    case (.en, .system): return "system audio"
    case (.en, .microphone): return "microphone"
    case (.en, .mixed): return "mixed"
    case (.de, .system): return "Systemaudio"
    case (.de, .microphone): return "Mikrofon"
    case (.de, .mixed): return "gemischte"
    }
  }

  private func normalizedMeetingTitle() -> String {
    let trimmed = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? strings.text(.meetingPlaceholder) : trimmed
  }

  private func previewSegments(from result: CaptureResult) -> [TranscriptSegment] {
    result.tracks.compactMap { track in
      guard let duration = track.duration else { return nil }
      return TranscriptSegment(
        id: "preview-\(track.kind.rawValue)",
        sourceTrack: track.kind,
        speakerLabel: speakerLabel(for: track.kind),
        start: track.startOffset ?? 0,
        end: (track.startOffset ?? 0) + min(duration, delaySeconds),
        text: statusText(.capturedTrackPreview(trackName(for: track.kind))),
        isDraft: true
      )
    }
  }
}
