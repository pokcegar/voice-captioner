import AppKit
import Foundation
import SwiftUI
import VoiceCaptionerAppModel
import VoiceCaptionerCore

struct ContentView: View {
    @StateObject private var viewModel: VoiceCaptionerAppModel

    init(viewModel: VoiceCaptionerAppModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            meetingList
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    captureSettings
                    modelSettings
                    recordingControls
                    transcriptionControls
                    capabilityStatus
                    transcriptPreview
                    selectedMeetingDetails
                    Text(viewModel.status)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(24)
                .frame(minWidth: 860, minHeight: 680, alignment: .topLeading)
            }
        }
        .task {
            viewModel.refreshAll()
            await viewModel.refreshPermissions()
        }
    }

    private var meetingList: some View {
        List(selection: $viewModel.selectedMeetingID) {
            ForEach(viewModel.meetings, id: \.metadata.id) { meeting in
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.metadata.title)
                        .font(.headline)
                    Text(meeting.metadata.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(meeting.metadata.status.rawValue)
                        .font(.caption2)
                        .foregroundStyle(statusColor(meeting.metadata.status))
                }
                .tag(Optional(meeting.metadata.id))
            }
        }
        .navigationTitle("Meetings")
        .toolbar {
            Button("Refresh") { viewModel.refreshAll() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VoiceCaptioner")
                .font(.largeTitle.bold())
            Text("Local-first recording, post-stop Whisper transcription, exports, and folder-indexed history. No cloud processing.")
                .foregroundStyle(.secondary)
        }
    }

    private var captureSettings: some View {
        Form {
            Section("Capture") {
                LabeledContent("Output root") {
                    HStack {
                        Text(viewModel.outputRoot.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…", action: chooseOutputRoot)
                    }
                }
                LabeledContent("Meeting title") {
                    TextField("Meeting", text: $viewModel.meetingTitle)
                        .frame(width: 280)
                }
                LabeledContent("Rolling delay") {
                    Stepper("\(Int(viewModel.delaySeconds)) seconds", value: $viewModel.delaySeconds, in: 10...120, step: 5)
                }
                LabeledContent("Chunk size") {
                    Stepper("\(Int(viewModel.chunkDurationSeconds)) seconds", value: $viewModel.chunkDurationSeconds, in: 10...300, step: 5)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var modelSettings: some View {
        Form {
            Section("Local Whisper") {
                LabeledContent("whisper.cpp executable") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(whisperExecutableLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack {
                            Button("Use Bundled", action: viewModel.useDefaultWhisperExecutable)
                            Button("Choose…", action: chooseWhisperExecutable)
                        }
                    }
                }
                LabeledContent("Downloaded model") {
                    Picker("Downloaded model", selection: $viewModel.selectedDownloadedModelPath) {
                        Text("Manual / none").tag(Optional<String>.none)
                        ForEach(viewModel.downloadedModels, id: \.model.localPath.path) { entry in
                            Text(modelLabel(entry)).tag(Optional(entry.model.localPath.path))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 360)
                    Button("Rescan") { viewModel.refreshModels() }
                }
                LabeledContent("Manual model") {
                    HStack {
                        Text(viewModel.manualModelURL?.path ?? "Optional .bin/.gguf model path")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…", action: chooseManualModel)
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
                Label("Start Recording", systemImage: "record.circle")
            }
            .disabled(!viewModel.canStartRecording)

            Button {
                Task { await viewModel.stopRecording() }
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .disabled(!viewModel.isRecording)

            Button("Refresh Permissions") {
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
                    Label("Transcribe Selected Meeting", systemImage: "waveform.and.magnifyingglass")
                }
                .disabled(!viewModel.canTranscribeSelectedMeeting)

                Button("Cancel") { viewModel.cancelTranscription() }
                    .disabled(!viewModel.transcriptionState.isRunning)

                Button("Regenerate Chunk Manifest") { viewModel.regenerateChunkPlan() }
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
            Text("After recording stops, choose a local model and executable, then transcribe to local Markdown/SRT/JSON exports.")
        case let .running(message):
            Text(message)
        case let .completed(segmentCount):
            Text("Completed with \(segmentCount) final segment(s).")
        case .cancelled:
            Text("Transcription cancelled.")
        case let .failed(message):
            Text("Transcription failed: \(message)")
        }
    }

    private var capabilityStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capabilities")
                .font(.headline)
            capabilityRow("Microphone", viewModel.permissionStatus?.microphone)
            capabilityRow("System audio", viewModel.permissionStatus?.systemAudio)
            capabilityRow("Output folder", viewModel.permissionStatus?.outputFolder)
            capabilityRow("Sandbox/entitlements", viewModel.permissionStatus?.sandboxEntitlement)
            capabilityRow("Model", viewModel.permissionStatus?.model)
        }
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript Preview")
                .font(.headline)
            if viewModel.rollingPreview.isEmpty {
                Text("Draft or final transcript segments appear here. Final exports stay in the selected meeting’s transcript folder.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.rollingPreview, id: \.id) { segment in
                    VStack(alignment: .leading) {
                        Text("\(segment.speakerLabel) • \(segment.sourceTrack.rawValue) • \(format(segment.start))-\(format(segment.end))")
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
            Text("Selected Meeting")
                .font(.headline)
            if let meeting = viewModel.selectedMeeting {
                Text(meeting.rootURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button("Open Folder") { NSWorkspace.shared.open(meeting.rootURL) }
                    ForEach(viewModel.exportArtifacts(for: meeting)) { artifact in
                        Button("Open \(artifact.label)") { NSWorkspace.shared.open(artifact.url) }
                            .disabled(!artifact.exists)
                    }
                }
                ForEach(meeting.metadata.tracks, id: \.id) { track in
                    Text("\(track.kind.rawValue): \(track.relativePath), \(track.duration.map { String(format: "%.3fs", $0) } ?? "duration pending"), \(track.timingConfidence.rawValue)")
                        .font(.caption)
                }
            } else {
                Text("No meeting selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func capabilityRow(_ label: String, _ status: CaptureCapabilityStatus?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(status?.readiness.rawValue ?? "unknown")
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
            return "No bundled executable found; choose a local whisper.cpp executable"
        }
        let source = viewModel.whisperExecutableSource ?? "manual"
        return "\(source): \(url.path)"
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
        let checksum = entry.model.checksum == nil ? "" : " • verified manifest"
        return "\(entry.model.name) • \(entry.recommendation)\(checksum)"
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
