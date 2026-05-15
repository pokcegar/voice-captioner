import AppKit
import SwiftUI
import VoiceCaptionerAppModel
import VoiceCaptionerCore

struct SettingsInspectorView: View {
  @ObservedObject var viewModel: VoiceCaptionerAppModel
  let chooseOutputRoot: () -> Void
  let chooseWhisperExecutable: () -> Void
  let chooseManualModel: () -> Void

  private var strings: AppStrings { viewModel.strings }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(strings.text(.settingsInspector))
          .font(.title2.bold())
        commonSettingsSection
        localWhisperSection
        liveDraftSettingsSection
        appSettingsSection
        diagnosticsDisclosureSection
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(.bar)
  }

  private var commonSettingsSection: some View {
    Form {
      Section(strings.text(.commonSettings)) {
        LabeledContent(strings.text(.meetingTitle)) {
          TextField(strings.text(.meetingPlaceholder), text: $viewModel.meetingTitle)
        }
        LabeledContent(strings.text(.outputRoot)) {
          VStack(alignment: .trailing, spacing: 4) {
            Text(viewModel.outputRoot.path)
              .lineLimit(1)
              .truncationMode(.middle)
            Button(strings.text(.choose), action: chooseOutputRoot)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var localWhisperSection: some View {
    Form {
      Section(strings.text(.localWhisper)) {
        LabeledContent(strings.text(.whisperExecutable)) {
          VStack(alignment: .trailing, spacing: 4) {
            Text(whisperExecutableLabel)
              .lineLimit(2)
              .truncationMode(.middle)
            HStack {
              Button(strings.text(.useBundled), action: viewModel.useDefaultWhisperExecutable)
              Button(strings.text(.choose), action: chooseWhisperExecutable)
            }
          }
        }

        LabeledContent(strings.text(.modelToDownload)) {
          VStack(alignment: .trailing, spacing: 6) {
            Picker(strings.text(.modelToDownload), selection: $viewModel.selectedModelDownload) {
              ForEach(WhisperModelSize.allCases) { model in
                Text(model.displayName).tag(model)
              }
            }
            .labelsHidden()
            Picker(strings.text(.modelMirror), selection: $viewModel.selectedModelDownloadMirror) {
              ForEach(WhisperModelDownloadMirror.allCases) { mirror in
                Text(mirrorLabel(mirror)).tag(mirror)
              }
            }
            .labelsHidden()
            HStack {
              if viewModel.modelDownloadState.isRunning {
                ProgressView()
                  .controlSize(.small)
                Button(strings.text(.cancel), action: viewModel.cancelModelDownload)
              }
              Button(strings.text(.downloadModel), action: viewModel.beginModelDownload)
                .disabled(!viewModel.canDownloadSelectedModel)
            }
            if let message = modelDownloadMessage {
              Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }
          }
        }
        LabeledContent(strings.text(.downloadedModel)) {
          VStack(alignment: .trailing, spacing: 4) {
            Picker(
              strings.text(.downloadedModel), selection: $viewModel.selectedDownloadedModelPath
            ) {
              Text(strings.text(.manualNone)).tag(Optional<String>.none)
              ForEach(viewModel.downloadedModels, id: \.model.localPath.path) { entry in
                Text(modelLabel(entry)).tag(Optional(entry.model.localPath.path))
              }
            }
            .labelsHidden()
            Button(strings.text(.rescan)) { viewModel.refreshModels() }
          }
        }
        LabeledContent(strings.text(.manualModel)) {
          VStack(alignment: .trailing, spacing: 4) {
            Text(viewModel.manualModelURL?.path ?? strings.text(.optionalModelPath))
              .lineLimit(2)
              .truncationMode(.middle)
            Button(strings.text(.choose), action: chooseManualModel)
          }
        }
      }
    }
    .formStyle(.grouped)
    .disabled(viewModel.isRecording)
    .opacity(viewModel.isRecording ? 0.65 : 1)
  }

  private var liveDraftSettingsSection: some View {
    Form {
      Section(strings.text(.liveDraftSettings)) {
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
    .disabled(viewModel.isRecording)
    .opacity(viewModel.isRecording ? 0.65 : 1)
  }

  private var appSettingsSection: some View {
    Form {
      Section(strings.text(.appSettings)) {
        LabeledContent(strings.text(.interfaceLanguage)) {
          Picker(
            strings.text(.interfaceLanguage),
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
        }
      }
    }
    .formStyle(.grouped)
  }

  private var diagnosticsDisclosureSection: some View {
    DisclosureGroup(strings.text(.advancedDiagnostics)) {
      VStack(alignment: .leading, spacing: 8) {
        Button(strings.text(.refreshPermissions)) {
          Task { await viewModel.refreshPermissions() }
        }
        Button(strings.text(.regenerateChunkManifest)) { viewModel.regenerateChunkPlan() }
          .disabled(viewModel.selectedMeeting == nil)
        capabilityRow(strings.text(.microphone), viewModel.permissionStatus?.microphone)
        capabilityRow(strings.text(.systemAudio), viewModel.permissionStatus?.systemAudio)
        capabilityRow(strings.text(.outputFolder), viewModel.permissionStatus?.outputFolder)
        capabilityRow(
          strings.text(.sandboxEntitlements), viewModel.permissionStatus?.sandboxEntitlement)
        capabilityRow(strings.text(.model), viewModel.permissionStatus?.model)
      }
      .padding(.top, 8)
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
    .font(.caption)
  }

  private var whisperExecutableLabel: String {
    guard let url = viewModel.whisperExecutableURL else {
      return strings.text(.noBundledExecutable)
    }
    let source = localizedExecutableSource(viewModel.whisperExecutableSource)
    return "\(source): \(url.path)"
  }

  private var modelDownloadMessage: String? {
    switch viewModel.modelDownloadState {
    case .idle:
      return nil
    case .running(let message), .completed(let message), .failed(let message):
      return message
    case .cancelled:
      return strings.text(.cancel)
    }
  }

  private func mirrorLabel(_ mirror: WhisperModelDownloadMirror) -> String {
    switch mirror {
    case .official:
      return strings.text(.officialMirror)
    case .hfMirror:
      return strings.text(.hfMirror)
    }
  }

  private func localizedExecutableSource(_ source: String?) -> String {
    switch source {
    case "bundled": return strings.text(.sourceBundled)
    case "project": return strings.text(.sourceProject)
    default: return strings.text(.sourceManual)
    }
  }

  private func modelLabel(_ entry: DownloadedWhisperModel) -> String {
    let checksum = entry.model.checksum == nil ? "" : " • \(strings.text(.verifiedManifest))"
    return "\(entry.model.name) • \(entry.recommendation)\(checksum)"
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
}
