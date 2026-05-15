import AppKit
import Foundation
import SwiftUI
import VoiceCaptionerAppModel
import VoiceCaptionerCore

struct ContentView: View {
  @StateObject private var viewModel: VoiceCaptionerAppModel

  private var strings: AppStrings { viewModel.strings }

  init(viewModel: VoiceCaptionerAppModel) {
    _viewModel = StateObject(wrappedValue: viewModel)
  }

  var body: some View {
    NavigationSplitView {
      meetingList
    } detail: {
      consoleLayout
    }
    .task {
      viewModel.refreshAll()
      await viewModel.refreshPermissions()
    }
  }

  private var meetingList: some View {
    List(
      selection: Binding(
        get: { viewModel.selectedMeetingID },
        set: { viewModel.selectMeeting(id: $0) }
      )
    ) {
      ForEach(viewModel.meetings, id: \.metadata.id) { meeting in
        VStack(alignment: .leading, spacing: 4) {
          Text(meeting.metadata.title)
            .font(.headline)
          Text(meeting.metadata.createdAt, style: .date)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(meetingStatusLabel(meeting.metadata.status))
            .font(.caption2)
            .foregroundStyle(statusColor(meeting.metadata.status))
        }
        .tag(Optional(meeting.metadata.id))
      }
    }
    .navigationTitle(strings.text(.meetings))
    .toolbar {
      Button(strings.text(.refresh)) { viewModel.refreshAll() }
    }
  }

  private var consoleLayout: some View {
    HStack(spacing: 0) {
      MeetingWorkspaceView(viewModel: viewModel)
        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      SettingsInspectorView(
        viewModel: viewModel,
        chooseOutputRoot: chooseOutputRoot,
        chooseWhisperExecutable: chooseWhisperExecutable,
        chooseManualModel: chooseManualModel
      )
      .frame(width: viewModel.isRecording ? 280 : 340)
      .background(.regularMaterial)
    }
    .frame(minWidth: 900, minHeight: 680)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("VoiceCaptioner")
        .font(.largeTitle.bold())
      Text(strings.text(.tagline))
        .foregroundStyle(.secondary)
    }
  }

  private var captureSettings: some View {
    Form {
      Section(strings.text(.capture)) {
        LabeledContent(strings.text(.language)) {
          Picker(
            strings.text(.language),
            selection: Binding(
              get: { viewModel.language },
              set: { viewModel.setLanguage($0) }
            )
          ) {
            ForEach(AppLanguage.allCases) { language in
              Text(language.displayName).tag(language)
            }
          }
          .labelsHidden()
          .frame(width: 180)
        }
        LabeledContent(strings.text(.outputRoot)) {
          HStack {
            Text(viewModel.outputRoot.path)
              .lineLimit(1)
              .truncationMode(.middle)
            Button(strings.text(.choose), action: chooseOutputRoot)
          }
        }
        LabeledContent(strings.text(.meetingTitle)) {
          TextField(strings.text(.meetingPlaceholder), text: $viewModel.meetingTitle)
            .frame(width: 280)
        }
        LabeledContent(strings.text(.rollingDelay)) {
          Stepper(
            strings.text(.seconds(Int(viewModel.delaySeconds))), value: $viewModel.delaySeconds,
            in: 10...120, step: 5)
        }
        LabeledContent(strings.text(.chunkSize)) {
          Stepper(
            strings.text(.seconds(Int(viewModel.chunkDurationSeconds))),
            value: $viewModel.chunkDurationSeconds, in: 10...300, step: 5)
        }
      }
    }
    .formStyle(.grouped)
  }

  private var modelSettings: some View {
    Form {
      Section(strings.text(.localWhisper)) {
        LabeledContent(strings.text(.whisperExecutable)) {
          VStack(alignment: .trailing, spacing: 4) {
            Text(whisperExecutableLabel)
              .lineLimit(1)
              .truncationMode(.middle)
            HStack {
              Button(strings.text(.useBundled), action: viewModel.useDefaultWhisperExecutable)
              Button(strings.text(.choose), action: chooseWhisperExecutable)
            }
          }
        }
        LabeledContent(strings.text(.downloadedModel)) {
          Picker(strings.text(.downloadedModel), selection: $viewModel.selectedDownloadedModelPath)
          {
            Text(strings.text(.manualNone)).tag(Optional<String>.none)
            ForEach(viewModel.downloadedModels, id: \.model.localPath.path) { entry in
              Text(modelLabel(entry)).tag(Optional(entry.model.localPath.path))
            }
          }
          .labelsHidden()
          .frame(width: 360)
          Button(strings.text(.rescan)) { viewModel.refreshModels() }
        }
        LabeledContent(strings.text(.manualModel)) {
          HStack {
            Text(viewModel.manualModelURL?.path ?? strings.text(.optionalModelPath))
              .lineLimit(1)
              .truncationMode(.middle)
            Button(strings.text(.choose), action: chooseManualModel)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var recordingControls: some View {
    HStack {
      Button {
        Task { await viewModel.startRecording() }
      } label: {
        Label(strings.text(.startRecording), systemImage: "record.circle")
      }
      .disabled(!viewModel.canStartRecording)

      Button {
        Task { await viewModel.stopRecording() }
      } label: {
        Label(strings.text(.stop), systemImage: "stop.circle")
      }
      .disabled(!viewModel.isRecording)

      Button(strings.text(.refreshPermissions)) {
        Task { await viewModel.refreshPermissions() }
      }
    }
  }

  private var transcriptionControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button {
          viewModel.beginTranscription()
        } label: {
          Label(
            strings.text(.transcribeSelectedMeeting), systemImage: "waveform.and.magnifyingglass")
        }
        .disabled(!viewModel.canTranscribeSelectedMeeting)

        Button(strings.text(.cancel)) { viewModel.cancelTranscription() }
          .disabled(!viewModel.transcriptionState.isRunning)

        Button(strings.text(.regenerateChunkManifest)) { viewModel.regenerateChunkPlan() }
          .disabled(viewModel.selectedMeeting == nil)
      }
      transcriptionStateText
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var transcriptionStateText: some View {
    switch viewModel.transcriptionState {
    case .idle:
      Text(strings.text(.idleTranscriptionHelp))
    case .running(let message):
      Text(message)
    case .completed(let segmentCount):
      Text(strings.text(.completedSegments(segmentCount)))
    case .cancelled:
      Text(strings.text(.transcriptionCancelled))
    case .failed(let message):
      Text(strings.text(.transcriptionFailed(message)))
    }
  }

  private var capabilityStatus: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(strings.text(.capabilities))
        .font(.headline)
      capabilityRow(strings.text(.microphone), viewModel.permissionStatus?.microphone)
      capabilityRow(strings.text(.systemAudio), viewModel.permissionStatus?.systemAudio)
      capabilityRow(strings.text(.outputFolder), viewModel.permissionStatus?.outputFolder)
      capabilityRow(
        strings.text(.sandboxEntitlements), viewModel.permissionStatus?.sandboxEntitlement)
      capabilityRow(strings.text(.model), viewModel.permissionStatus?.model)
    }
  }

  private var transcriptPreview: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(strings.text(.transcriptPreview))
        .font(.headline)
      if viewModel.rollingPreview.isEmpty {
        Text(strings.text(.transcriptPreviewEmpty))
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.rollingPreview, id: \.id) { segment in
          VStack(alignment: .leading) {
            Text(
              "\(segment.speakerLabel) • \(segment.sourceTrack.rawValue) • \(format(segment.start))-\(format(segment.end))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(segment.text)
          }
          .padding(8)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
      }
    }
  }

  private var selectedMeetingDetails: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(strings.text(.selectedMeeting))
        .font(.headline)
      if let meeting = viewModel.selectedMeeting {
        Text(meeting.rootURL.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        HStack {
          Button(strings.text(.openFolder)) { NSWorkspace.shared.open(meeting.rootURL) }
          ForEach(viewModel.exportArtifacts(for: meeting)) { artifact in
            Button(strings.text(.openArtifact(artifact.label))) {
              NSWorkspace.shared.open(artifact.url)
            }
            .disabled(!artifact.exists)
          }
        }
        ForEach(meeting.metadata.tracks, id: \.id) { track in
          Text(
            "\(trackKindLabel(track.kind)): \(track.relativePath), \(track.duration.map { String(format: "%.3fs", $0) } ?? strings.text(.durationPending)), \(timingConfidenceLabel(track.timingConfidence))"
          )
          .font(.caption)
        }
      } else {
        Text(strings.text(.noMeetingSelected))
          .foregroundStyle(.secondary)
      }
    }
  }

  private func capabilityRow(_ label: String, _ status: CaptureCapabilityStatus?) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(readinessLabel(status?.readiness))
        .foregroundStyle(status?.isReady == true ? .green : .secondary)
      if let message = status?.message {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var whisperExecutableLabel: String {
    guard let url = viewModel.whisperExecutableURL else {
      return strings.text(.noBundledExecutable)
    }
    let source = localizedExecutableSource(viewModel.whisperExecutableSource)
    return "\(source): \(url.path)"
  }

  private func localizedExecutableSource(_ source: String?) -> String {
    switch source {
    case "bundled": return strings.text(.sourceBundled)
    case "project": return strings.text(.sourceProject)
    default: return strings.text(.sourceManual)
    }
  }

  private func chooseOutputRoot() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = viewModel.outputRoot
    if panel.runModal() == .OK, let url = panel.url {
      viewModel.setOutputRoot(url)
    }
  }

  private func chooseWhisperExecutable() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      viewModel.setWhisperExecutable(url)
    }
  }

  private func chooseManualModel() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(filePath: FileManager.default.currentDirectoryPath)
      .appending(path: "Models", directoryHint: .isDirectory)
    if panel.runModal() == .OK, let url = panel.url {
      viewModel.setManualModel(url)
    }
  }

  private func modelLabel(_ entry: DownloadedWhisperModel) -> String {
    let checksum = entry.model.checksum == nil ? "" : " • \(strings.text(.verifiedManifest))"
    return "\(entry.model.name) • \(entry.recommendation)\(checksum)"
  }

  private func meetingStatusLabel(_ status: MeetingStatus) -> String {
    switch (viewModel.language, status) {
    case (.zhHans, .recording): return "录音中"
    case (.zhHans, .finalizing): return "完成中"
    case (.zhHans, .complete): return "已完成"
    case (.zhHans, .interrupted): return "已中断"
    case (.en, .recording): return "recording"
    case (.en, .finalizing): return "finalizing"
    case (.en, .complete): return "complete"
    case (.en, .interrupted): return "interrupted"
    case (.de, .recording): return "Aufnahme"
    case (.de, .finalizing): return "Abschluss"
    case (.de, .complete): return "abgeschlossen"
    case (.de, .interrupted): return "unterbrochen"
    }
  }

  private func readinessLabel(_ readiness: CapabilityReadiness?) -> String {
    guard let readiness else { return strings.text(.statusUnknown) }
    switch (viewModel.language, readiness) {
    case (.zhHans, .ready): return "就绪"
    case (.zhHans, .denied): return "已拒绝"
    case (.zhHans, .notDetermined): return "未确定"
    case (.zhHans, .unavailable): return "不可用"
    case (.zhHans, .notConfigured): return "未配置"
    case (.zhHans, .unknown): return "未知"
    case (.en, _): return readiness.rawValue
    case (.de, .ready): return "bereit"
    case (.de, .denied): return "verweigert"
    case (.de, .notDetermined): return "nicht bestimmt"
    case (.de, .unavailable): return "nicht verfügbar"
    case (.de, .notConfigured): return "nicht konfiguriert"
    case (.de, .unknown): return "unbekannt"
    }
  }

  private func trackKindLabel(_ kind: AudioTrackKind) -> String {
    switch (viewModel.language, kind) {
    case (.zhHans, .system): return "系统音频"
    case (.zhHans, .microphone): return "麦克风"
    case (.zhHans, .mixed): return "混合"
    case (.en, _): return kind.rawValue
    case (.de, .system): return "Systemaudio"
    case (.de, .microphone): return "Mikrofon"
    case (.de, .mixed): return "gemischt"
    }
  }

  private func timingConfidenceLabel(_ confidence: TrackTimingConfidence) -> String {
    switch (viewModel.language, confidence) {
    case (.zhHans, .observed): return "已观测"
    case (.zhHans, .inferred): return "已推断"
    case (.zhHans, .unknown): return "未知"
    case (.en, _): return confidence.rawValue
    case (.de, .observed): return "beobachtet"
    case (.de, .inferred): return "abgeleitet"
    case (.de, .unknown): return "unbekannt"
    }
  }

  private func statusColor(_ status: MeetingStatus) -> Color {
    switch status {
    case .recording: return .red
    case .finalizing: return .orange
    case .complete: return .green
    case .interrupted: return .yellow
    }
  }

  private func format(_ seconds: TimeInterval) -> String {
    String(format: "%.1fs", seconds)
  }
}
