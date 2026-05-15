import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("MeetingStore")
struct MeetingStoreTests {
    @Test func createsMeetingFolderWithMetadataAndTracks() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let folder = try store.createMeeting(
            outputRoot: root,
            title: "Design Review",
            now: date,
            delaySeconds: 45
        )

        #expect(FileManager.default.fileExists(atPath: folder.audioDirectory.path))
        #expect(FileManager.default.fileExists(atPath: folder.chunksDirectory.path))
        #expect(FileManager.default.fileExists(atPath: folder.transcriptDirectory.path))
        #expect(FileManager.default.fileExists(atPath: folder.metadataURL.path))

        let metadata = try store.readMetadata(at: folder.metadataURL)
        #expect(metadata.title == "Design Review")
        #expect(metadata.status == .recording)
        #expect(metadata.transcriptionDelaySeconds == 45)
        #expect(metadata.tracks.map(\.kind) == [.system, .microphone])
    }

    @Test func scanMeetingsIgnoresMalformedFoldersAndSortsNewestFirst() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore()
        _ = try store.createMeeting(outputRoot: root, title: "Older", now: Date(timeIntervalSince1970: 10))
        _ = try store.createMeeting(outputRoot: root, title: "Newer", now: Date(timeIntervalSince1970: 20))
        let malformed = root.appending(path: "broken", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: malformed.appending(path: "metadata.json"))

        let meetings = try store.scanMeetings(outputRoot: root)

        #expect(meetings.count == 2)
        #expect(meetings[0].metadata.title == "Newer")
        #expect(meetings[1].metadata.title == "Older")
    }
}

func temporaryDirectory() throws -> URL {
    let projectRoot = URL(filePath: FileManager.default.currentDirectoryPath)
    let url = projectRoot
        .appending(path: ".tmp/tests/voice-captioner-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
