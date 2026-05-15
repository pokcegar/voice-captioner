import Foundation
import Testing
import VoiceCaptionerCore

@testable import VoiceCaptionerAppModel

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
    try Data(
      """
      {"filename":"ggml-small.bin","sha256":"abc","status":"downloaded"}
      """.utf8
    ).write(to: models.appending(path: "ggml-small.manifest.json"))

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
    #expect(model.status == "就绪 — 本地录音与转写")
    #expect(model.strings.text(.startRecording) == "开始录音")

    model.refreshModels()
    #expect(model.status.contains("未找到已下载的 Whisper 模型"))

    model.setLanguage(.en)
    #expect(model.status == "Ready — local-only recording and transcription")
    #expect(model.strings.text(.startRecording) == "Start Recording")

    model.setLanguage(.de)
    #expect(model.status == "Bereit — lokale Aufnahme und Transkription")
    #expect(model.strings.text(.startRecording) == "Aufnahme starten")
  }


  @Test @MainActor func startRecordingEnablesDelayedLiveDraftsWhenLocalWhisperIsReady() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let models = root.appending(path: "Models", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
    let modelURL = models.appending(path: "ggml-small.bin", directoryHint: .notDirectory)
    let executable = root.appending(path: "whisper-cli", directoryHint: .notDirectory)
    try Data("model".utf8).write(to: modelURL)
    try Data("#!/bin/sh\n".utf8).write(to: executable)
    let liveWorkflow = FakeLiveTranscriptionWorkflow()
    let model = VoiceCaptionerAppModel(
      outputRoot: root.appending(path: "Meetings", directoryHint: .isDirectory),
      delaySeconds: 0.05,
      chunkDurationSeconds: 5,
      provider: FakeAudioCaptureProvider(),
      modelsDirectory: models,
      transcriptionWorkflow: FakeTranscriptionWorkflow(),
      liveTranscriptionWorkflow: liveWorkflow,
      defaultWhisperExecutable: WhisperExecutableCandidate(url: executable, source: "bundled")
    )
    model.refreshModels()

    await model.startRecording()
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(model.rollingPreview.map { $0.text } == ["live draft"])
    #expect(model.status.contains("延迟实时转写已更新"))
    #expect((liveWorkflow.pipeline?.pollCount() ?? 0) >= 1)
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

  @Test @MainActor func transcribeSelectedMeetingRequiresLocalExecutableAndWritesExports()
    async throws
  {
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
      AudioTrack(
        id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0,
        timingConfidence: .observed, duration: 1)
    ]
    try MeetingStore().writeMetadata(metadata, to: meeting.metadataURL)
    let workflow = FakeTranscriptionWorkflow()
    let model = VoiceCaptionerAppModel(
      outputRoot: root,
      provider: FakeAudioCaptureProvider(),
      modelsDirectory: models,
      transcriptionWorkflow: workflow,
      liveTranscriptionWorkflow: nil
    )
    model.refreshAll()
    model.setManualModel(modelURL)
    model.setWhisperExecutable(executable)

    await model.transcribeSelectedMeeting()

    #expect(model.transcriptionState == .completed(segmentCount: 1))
    #expect(model.rollingPreview.map(\.text) == ["done"])
    let exports = model.exportArtifacts()
    #expect(exports.map(\.label) == ["Machine Markdown", "SRT", "JSON", "Edited Markdown"])
    #expect(exports.map(\.exists) == [true, true, true, false])
    #expect(await workflow.runCount() == 1)
  }

  @Test @MainActor func loadsFinalMarkdownAsEditableDraftWhenNoEditedMarkdownExists() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = try completedMeeting(in: root, title: "Final Draft")
    let finalURL = meeting.transcriptDirectory.appending(path: "final.md")
    try "machine markdown".write(to: finalURL, atomically: true, encoding: .utf8)

    let model = makeAppModel(outputRoot: root)
    model.refreshHistoryPreservingSelection()

    #expect(model.selectedMeetingID == meeting.metadata.id)
    #expect(model.editableMarkdownText == "machine markdown")
    #expect(model.editableMarkdownSource == .finalMarkdown)
    #expect(!model.isEditableMarkdownDirty)
  }

  @Test @MainActor func savingEditableMarkdownWritesEditedMarkdownWithoutChangingFinal() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = try completedMeeting(in: root, title: "Save Edited")
    let finalURL = meeting.transcriptDirectory.appending(path: "final.md")
    let editedURL = meeting.transcriptDirectory.appending(path: "edited.md")
    try "machine original".write(to: finalURL, atomically: true, encoding: .utf8)
    let model = makeAppModel(outputRoot: root)
    model.refreshHistoryPreservingSelection()

    model.updateEditableMarkdownText("user edited")
    model.saveEditableMarkdown()

    #expect(try String(contentsOf: editedURL, encoding: .utf8) == "user edited")
    #expect(try String(contentsOf: finalURL, encoding: .utf8) == "machine original")
    #expect(model.editableMarkdownSource == .editedMarkdown)
    #expect(!model.isEditableMarkdownDirty)
  }

  @Test @MainActor func loadsEditedMarkdownBeforeFinalMarkdown() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = try completedMeeting(in: root, title: "Edited First")
    try "machine".write(to: meeting.transcriptDirectory.appending(path: "final.md"), atomically: true, encoding: .utf8)
    try "edited".write(to: meeting.transcriptDirectory.appending(path: "edited.md"), atomically: true, encoding: .utf8)

    let model = makeAppModel(outputRoot: root)
    model.refreshHistoryPreservingSelection()

    #expect(model.editableMarkdownText == "edited")
    #expect(model.editableMarkdownSource == .editedMarkdown)
  }

  @Test @MainActor func exportArtifactsIncludesEditedMarkdown() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let meeting = try completedMeeting(in: root, title: "Exports")
    try "md".write(to: meeting.transcriptDirectory.appending(path: "final.md"), atomically: true, encoding: .utf8)
    try "srt".write(to: meeting.transcriptDirectory.appending(path: "final.srt"), atomically: true, encoding: .utf8)
    try Data("{}".utf8).write(to: meeting.transcriptDirectory.appending(path: "final.json"))

    let model = makeAppModel(outputRoot: root)
    model.refreshHistoryPreservingSelection()
    let artifacts = model.exportArtifacts(for: meeting)

    #expect(artifacts.map(\.label) == ["Machine Markdown", "SRT", "JSON", "Edited Markdown"])
    #expect(artifacts.map(\.exists) == [true, true, true, false])
  }

  @Test @MainActor func transcriptionCompletionDoesNotOverwriteExistingEditedMarkdown() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let models = root.appending(path: "Models", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
    let modelURL = models.appending(path: "ggml-small.bin", directoryHint: .notDirectory)
    let executable = root.appending(path: "whisper-cli", directoryHint: .notDirectory)
    try Data("model".utf8).write(to: modelURL)
    try Data("#!/bin/sh
".utf8).write(to: executable)
    let meeting = try completedMeeting(in: root, title: "Retranscribe")
    try "user edits".write(to: meeting.transcriptDirectory.appending(path: "edited.md"), atomically: true, encoding: .utf8)
    let workflow = FakeTranscriptionWorkflow()
    let model = VoiceCaptionerAppModel(
      outputRoot: root,
      provider: FakeAudioCaptureProvider(),
      modelsDirectory: models,
      transcriptionWorkflow: workflow,
      liveTranscriptionWorkflow: nil
    )
    model.refreshAll()
    model.setManualModel(modelURL)
    model.setWhisperExecutable(executable)

    await model.transcribeSelectedMeeting()

    #expect(try String(contentsOf: meeting.transcriptDirectory.appending(path: "edited.md"), encoding: .utf8) == "user edits")
    #expect(model.editableMarkdownText == "user edits")
    #expect(model.editableMarkdownSource == .editedMarkdown)
  }

  @Test @MainActor func selectingAnotherMeetingAutosavesDirtyMarkdownToOriginalMeeting() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let older = Date(timeIntervalSince1970: 100)
    let newer = Date(timeIntervalSince1970: 200)
    let meetingA = try completedMeeting(in: root, title: "A", now: newer)
    let meetingB = try completedMeeting(in: root, title: "B", now: older)
    try "A final".write(to: meetingA.transcriptDirectory.appending(path: "final.md"), atomically: true, encoding: .utf8)
    try "B final".write(to: meetingB.transcriptDirectory.appending(path: "final.md"), atomically: true, encoding: .utf8)
    let model = makeAppModel(outputRoot: root)
    model.refreshHistoryPreservingSelection()

    model.updateEditableMarkdownText("A autosaved")
    model.selectMeeting(id: meetingB.metadata.id)

    #expect(try String(contentsOf: meetingA.transcriptDirectory.appending(path: "edited.md"), encoding: .utf8) == "A autosaved")
    #expect(model.editableMarkdownMeetingID == meetingB.metadata.id)
    #expect(model.editableMarkdownText == "B final")
  }

  @Test @MainActor func saveEditableMarkdownWritesToLoadedMeetingNotCurrentSelectionRace() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let meetingA = try completedMeeting(in: root, title: "A", now: Date(timeIntervalSince1970: 200))
    let meetingB = try completedMeeting(in: root, title: "B", now: Date(timeIntervalSince1970: 100))
    try "A final".write(to: meetingA.transcriptDirectory.appending(path: "final.md"), atomically: true, encoding: .utf8)
    try "B final".write(to: meetingB.transcriptDirectory.appending(path: "final.md"), atomically: true, encoding: .utf8)
    let model = makeAppModel(outputRoot: root)
    model.refreshHistoryPreservingSelection()

    model.selectedMeetingID = meetingB.metadata.id
    model.updateEditableMarkdownText("still A")
    model.saveEditableMarkdown()

    #expect(try String(contentsOf: meetingA.transcriptDirectory.appending(path: "edited.md"), encoding: .utf8) == "still A")
    #expect(!FileManager.default.fileExists(atPath: meetingB.transcriptDirectory.appending(path: "edited.md").path))
  }

  @Test @MainActor func localizationHasExplicitInterfaceTranscriptionAndMarkdownLabels() throws {
    #expect(AppStrings(language: .zhHans).text(.interfaceLanguage) == "界面语言")
    #expect(AppStrings(language: .zhHans).text(.fixedChineseTranscriptionLanguage) == "转写语言：中文")
    #expect(AppStrings(language: .zhHans).text(.editedMarkdown) == "用户编辑版 Markdown")
    #expect(AppStrings(language: .en).text(.interfaceLanguage) == "Interface Language")
    #expect(AppStrings(language: .de).text(.editedMarkdown) == "Bearbeitetes Markdown")
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
    try FileManager.default.createDirectory(
      at: meeting.transcriptDirectory, withIntermediateDirectories: true)
    try TranscriptExporter.markdown(meeting: meeting.metadata, segments: [segment])
      .write(
        to: meeting.transcriptDirectory.appending(path: "final.md"), atomically: true,
        encoding: .utf8)
    try TranscriptExporter.srt(segments: [segment])
      .write(
        to: meeting.transcriptDirectory.appending(path: "final.srt"), atomically: true,
        encoding: .utf8)
    try TranscriptExporter.json(segments: [segment])
      .write(to: meeting.transcriptDirectory.appending(path: "final.json"), options: .atomic)
    return RollingTranscriptionResult(
      chunks: [], rollingSegments: [segment], finalSegments: [segment])
  }
}

private final class FakeLiveTranscriptionWorkflow: LiveTranscriptionWorkflow, @unchecked Sendable {
  var pipeline: FakeLiveTranscriptionPipeline?

  func makePipeline(whisperExecutableURL: URL) -> LiveTranscriptionPipeline {
    let pipeline = FakeLiveTranscriptionPipeline()
    self.pipeline = pipeline
    return pipeline
  }
}

private final class FakeLiveTranscriptionPipeline: LiveTranscriptionPipeline, @unchecked Sendable {
  private let lock = NSLock()
  private var polls = 0

  init() {
    super.init(transcriber: FakeNoopTranscriber())
  }

  func pollCount() -> Int {
    lock.withLock { polls }
  }

  private func incrementPolls() {
    lock.withLock { polls += 1 }
  }

  override func poll(
    meeting: MeetingFolder,
    model: WhisperModel,
    chunkDuration: TimeInterval,
    trailingSafetyMargin: TimeInterval = 1.0
  ) async throws -> LiveTranscriptionUpdate {
    incrementPolls()
    return LiveTranscriptionUpdate(
      chunks: [],
      draftSegments: [
        TranscriptSegment(
          id: "live-1",
          sourceTrack: .microphone,
          speakerLabel: "Local",
          start: 0,
          end: 1,
          text: "live draft",
          isDraft: true
        )
      ]
    )
  }
}

private struct FakeNoopTranscriber: TranscriptionProvider {
  func transcribe(chunk: AudioChunk, model: WhisperModel) async throws -> [TranscriptSegment] { [] }
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
      AudioTrack(
        id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0,
        timingConfidence: .observed, duration: 1),
      AudioTrack(
        id: "microphone", kind: .microphone, relativePath: "audio/microphone.wav", startOffset: 0,
        timingConfidence: .observed, duration: 1),
    ]
    folder.metadata.status = .complete
    folder.metadata.tracks = tracks
    try store.writeMetadata(folder.metadata, to: folder.metadataURL)
    return CaptureResult(handle: handle, status: .complete, tracks: tracks)
  }
}


@MainActor
private func makeAppModel(outputRoot: URL) -> VoiceCaptionerAppModel {
  VoiceCaptionerAppModel(
    outputRoot: outputRoot,
    provider: FakeAudioCaptureProvider(),
    modelsDirectory: outputRoot.appending(path: "Models", directoryHint: .isDirectory),
    transcriptionWorkflow: FakeTranscriptionWorkflow(),
    liveTranscriptionWorkflow: nil,
    defaultWhisperExecutable: nil
  )
}

private func completedMeeting(in root: URL, title: String, now: Date = Date()) throws -> MeetingFolder {
  let store = MeetingStore()
  let meeting = try store.createMeeting(outputRoot: root, title: title, now: now)
  var metadata = meeting.metadata
  metadata.status = .complete
  metadata.tracks = [
    AudioTrack(
      id: "system", kind: .system, relativePath: "audio/system.wav", startOffset: 0,
      timingConfidence: .observed, duration: 1)
  ]
  try store.writeMetadata(metadata, to: meeting.metadataURL)
  return MeetingFolder(rootURL: meeting.rootURL, metadata: metadata)
}

private func temporaryDirectory() throws -> URL {
  let projectRoot = URL(filePath: FileManager.default.currentDirectoryPath)
  let url =
    projectRoot
    .appending(
      path: ".tmp/tests/voice-captioner-app-model-\(UUID().uuidString)", directoryHint: .isDirectory
    )
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
