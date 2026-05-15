import AppKit
import Foundation
import SwiftUI
import VoiceCaptionerCore

@main
struct VoiceCaptionerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var outputRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "VoiceCaptionerMeetings", directoryHint: .isDirectory)
    @Published var delaySeconds = 30.0
    @Published var meetingTitle = "Meeting"
    @Published var meetings: [MeetingFolder] = []
    @Published var selectedMeetingID: String?
    @Published var permissionStatus: PermissionStatus?
    @Published var status = "Ready"
    @Published var isRecording = false
    @Published var activeMeeting: MeetingFolder?
    @Published var captureResult: CaptureResult?
    @Published var modelPath = ""
    @Published var rollingPreview: [TranscriptSegment] = []

    private let store = MeetingStore()
    private let provider = NativeMacCaptureProvider(captureGatePassed: true)
    private var activeHandle: CaptureHandle?

    var selectedMeeting: MeetingFolder? {
        meetings.first { $0.metadata.id == selectedMeetingID }
    }

    func refresh() {
        do {
            meetings = try store.scanMeetings(outputRoot: outputRoot)
            if selectedMeetingID == nil || !meetings.contains(where: { $0.metadata.id == selectedMeetingID }) {
                selectedMeetingID = meetings.first?.metadata.id
            }
            status = "Indexed \(meetings.count) meeting folder(s)"
        } catch {
            status = "History error: \(error.localizedDescription)"
        }
    }

    func refreshPermissions() async {
        do {
            permissionStatus = try await provider.requestPermissions()
        } catch {
            status = "Permission check failed: \(error.localizedDescription)"
        }
    }

    func chooseOutputRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputRoot
        if panel.runModal() == .OK, let url = panel.url {
            outputRoot = url
            refresh()
        }
    }

    func chooseModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.directoryURL = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "Models", directoryHint: .isDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            modelPath = url.path
        }
    }

    func startRecording() async {
        guard !isRecording else { return }
        do {
            let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Meeting" : meetingTitle
            let meeting = try store.createMeeting(outputRoot: outputRoot, title: title, delaySeconds: delaySeconds)
            let handle = try await provider.start(session: CaptureSessionConfig(outputFolder: meeting))
            activeMeeting = meeting
            activeHandle = handle
            captureResult = nil
            rollingPreview = []
            isRecording = true
            status = "Recording \(meeting.metadata.title)…"
            refresh()
        } catch {
            status = "Start failed: \(error.localizedDescription)"
        }
    }

    func stopRecording() async {
        guard let handle = activeHandle else { return }
        do {
            status = "Finalizing capture…"
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
                ? "Capture complete: \(result.tracks.count) track(s), drift \(formatSeconds(result.drift?.estimatedDriftSeconds))"
                : "Capture interrupted: \(result.failures.map(\.message).joined(separator: "; "))"
            refresh()
        } catch {
            status = "Stop failed: \(error.localizedDescription)"
        }
    }

    func openSelectedFolder() {
        guard let selectedMeeting else { return }
        NSWorkspace.shared.open(selectedMeeting.rootURL)
    }

    func regenerateChunkPlan() {
        guard let selectedMeeting else { return }
        do {
            let chunks = try AudioChunker.planChunks(for: selectedMeeting)
            try AudioChunker.writeManifest(chunks, to: selectedMeeting.chunksDirectory.appending(path: "chunks.json"))
            status = "Regenerated \(chunks.count) chunk work item(s)"
        } catch {
            status = "Chunk plan failed: \(error.localizedDescription)"
        }
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
                text: "Captured \(track.kind.rawValue) track; transcription pending model workflow.",
                isDraft: true
            )
        }
    }

    private func formatSeconds(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "n/a" }
        return String(format: "%.3fs", seconds)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = RecordingViewModel()

    var body: some View {
        NavigationSplitView {
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
                Button("Refresh") { viewModel.refresh() }
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    settings
                    controls
                    capabilityStatus
                    transcriptPreview
                    selectedMeetingDetails
                    Text(viewModel.status)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(minWidth: 760, minHeight: 560, alignment: .topLeading)
            }
        }
        .task {
            viewModel.refresh()
            await viewModel.refreshPermissions()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VoiceCaptioner")
                .font(.largeTitle.bold())
            Text("Local-first dual-track recording with delayed rolling transcription scaffolding.")
                .foregroundStyle(.secondary)
        }
    }

    private var settings: some View {
        Form {
            LabeledContent("Output root") {
                HStack {
                    Text(viewModel.outputRoot.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { viewModel.chooseOutputRoot() }
                }
            }
            LabeledContent("Meeting title") {
                TextField("Meeting", text: $viewModel.meetingTitle)
                    .frame(width: 280)
            }
            LabeledContent("Rolling delay") {
                Stepper("\(Int(viewModel.delaySeconds)) seconds", value: $viewModel.delaySeconds, in: 10...120, step: 5)
            }
            LabeledContent("Whisper model") {
                HStack {
                    Text(viewModel.modelPath.isEmpty ? "Not selected; recording still allowed" : viewModel.modelPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { viewModel.chooseModel() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var controls: some View {
        HStack {
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
            }
            .disabled(viewModel.isRecording)

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
            Text("Rolling Transcript Preview")
                .font(.headline)
            if viewModel.rollingPreview.isEmpty {
                Text("Draft transcript segments will appear here after chunk/transcription pipeline integration. Current workflow records separated tracks and can regenerate chunk manifests.")
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
                    Button("Open Folder") { viewModel.openSelectedFolder() }
                    Button("Regenerate Chunk Manifest") { viewModel.regenerateChunkPlan() }
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
