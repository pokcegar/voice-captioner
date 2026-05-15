import AppKit
import SwiftUI
import VoiceCaptionerAppModel
import VoiceCaptionerCore

struct MeetingWorkspaceView: View {
  @ObservedObject var viewModel: VoiceCaptionerAppModel
  let openMeetingFolder: (MeetingFolder) -> Void
  let openArtifact: (TranscriptExportArtifact) -> Void

  private var strings: AppStrings { viewModel.strings }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        workspaceHeader
        primaryControls
        TranscriptSegmentsView(viewModel: viewModel)
        MarkdownEditorPanel(viewModel: viewModel)
        meetingArtifactsPanel
        Text(viewModel.status)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private var workspaceHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(strings.text(.currentMeetingWorkspace))
        .font(.largeTitle.bold())
      Text(strings.text(.tagline))
        .foregroundStyle(.secondary)
      LabeledContent(strings.text(.transcriptionLanguage)) {
        Text(strings.text(.fixedChineseTranscriptionLanguage))
          .font(.callout.weight(.semibold))
      }
    }
  }

  private var primaryControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Button {
          Task { await viewModel.startRecording() }
        } label: {
          Label(strings.text(.startRecording), systemImage: "record.circle")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canStartRecording)

        Button {
          Task { await viewModel.stopRecording() }
        } label: {
          Label(strings.text(.stop), systemImage: "stop.circle")
        }
        .disabled(!viewModel.isRecording)

        Button {
          viewModel.beginTranscription()
        } label: {
          Label(strings.text(.transcribeSelectedMeeting), systemImage: "waveform.and.magnifyingglass")
        }
        .disabled(!viewModel.canTranscribeSelectedMeeting)

        Button(strings.text(.cancel)) { viewModel.cancelTranscription() }
          .disabled(!viewModel.transcriptionState.isRunning)
      }

      transcriptionStateText
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
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

  private var meetingArtifactsPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(strings.text(.selectedMeeting))
        .font(.headline)
      if let meeting = viewModel.selectedMeeting {
        Text(meeting.rootURL.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        HStack {
          Button(strings.text(.openFolder)) { openMeetingFolder(meeting) }
          ForEach(viewModel.exportArtifacts(for: meeting)) { artifact in
            Button(strings.text(.openArtifact(localizedArtifactLabel(artifact.label)))) {
              openArtifact(artifact)
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

  private func localizedArtifactLabel(_ label: String) -> String {
    switch label {
    case "Machine Markdown": return strings.text(.machineMarkdown)
    case "Edited Markdown": return strings.text(.editedMarkdown)
    default: return label
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
}
