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
    List(selection: Binding(get: { viewModel.selectedMeetingID }, set: { viewModel.selectMeeting(id: $0) })) {
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
      MeetingWorkspaceView(
        viewModel: viewModel,
        openMeetingFolder: { NSWorkspace.shared.open($0.rootURL) },
        openArtifact: { NSWorkspace.shared.open($0.url) }
      )
      .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      SettingsInspectorView(
        viewModel: viewModel,
        chooseOutputRoot: chooseOutputRoot,
        chooseWhisperExecutable: chooseWhisperExecutable,
        chooseManualModel: chooseManualModel
      )
      .frame(width: viewModel.isRecording ? 280 : 340)
    }
    .frame(minWidth: 900, minHeight: 680)
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

  private func statusColor(_ status: MeetingStatus) -> Color {
    switch status {
    case .recording: return .red
    case .finalizing: return .orange
    case .complete: return .green
    case .interrupted: return .yellow
    }
  }
}
