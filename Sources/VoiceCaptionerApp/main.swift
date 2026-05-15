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

struct ContentView: View {
    @State private var outputRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "VoiceCaptionerMeetings", directoryHint: .isDirectory)
    @State private var delaySeconds = 30.0
    @State private var meetings: [MeetingFolder] = []
    @State private var status = "Ready"

    private let store = MeetingStore()

    var body: some View {
        NavigationSplitView {
            List(meetings, id: \.metadata.id) { meeting in
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.metadata.title)
                        .font(.headline)
                    Text(meeting.metadata.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Meetings")
            .toolbar {
                Button("Refresh") {
                    refreshHistory()
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                Text("VoiceCaptioner")
                    .font(.largeTitle.bold())
                Text("Local-first meeting capture and delayed transcription.")
                    .foregroundStyle(.secondary)

                Form {
                    LabeledContent("Output root") {
                        Text(outputRoot.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    LabeledContent("Transcription delay") {
                        Stepper("\(Int(delaySeconds)) seconds", value: $delaySeconds, in: 10...120, step: 5)
                    }

                    LabeledContent("Whole-system audio") {
                        Text("Blocked by capture gate")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Microphone track") {
                        Text("Blocked by capture gate")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Mixed export") {
                        Text("Planned after source tracks")
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Button("Create Test Meeting Folder") {
                        createTestMeeting()
                    }
                    Button("Refresh History") {
                        refreshHistory()
                    }
                }

                Text(status)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 680, minHeight: 460)
        }
        .onAppear {
            refreshHistory()
        }
    }

    private func createTestMeeting() {
        do {
            let folder = try store.createMeeting(
                outputRoot: outputRoot,
                title: "Test Meeting",
                delaySeconds: delaySeconds
            )
            status = "Created \(folder.rootURL.lastPathComponent)"
            refreshHistory()
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func refreshHistory() {
        do {
            meetings = try store.scanMeetings(outputRoot: outputRoot)
            status = "Indexed \(meetings.count) meeting folder(s)"
        } catch {
            status = "History error: \(error.localizedDescription)"
        }
    }
}
