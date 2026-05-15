import Foundation

public struct MeetingFolder: Equatable, Sendable {
    public var rootURL: URL
    public var metadata: MeetingMetadata

    public var audioDirectory: URL { rootURL.appending(path: "audio", directoryHint: .isDirectory) }
    public var chunksDirectory: URL { rootURL.appending(path: "chunks", directoryHint: .isDirectory) }
    public var transcriptDirectory: URL { rootURL.appending(path: "transcript", directoryHint: .isDirectory) }
    public var metadataURL: URL { rootURL.appending(path: "metadata.json", directoryHint: .notDirectory) }

    public init(rootURL: URL, metadata: MeetingMetadata) {
        self.rootURL = rootURL
        self.metadata = metadata
    }
}

public enum MeetingStoreError: Error, Equatable {
    case malformedMetadata(URL)
}

public final class MeetingStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func createMeeting(
        outputRoot: URL,
        title: String,
        now: Date = Date(),
        delaySeconds: TimeInterval = 30
    ) throws -> MeetingFolder {
        let id = Self.slug(for: title, date: now)
        let root = outputRoot.appending(path: id, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appending(path: "audio", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appending(path: "chunks", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appending(path: "transcript", directoryHint: .isDirectory), withIntermediateDirectories: true)

        let metadata = MeetingMetadata(
            id: id,
            title: title,
            createdAt: now,
            updatedAt: now,
            status: .recording,
            sessionClockStart: now,
            transcriptionDelaySeconds: delaySeconds,
            tracks: [
                AudioTrack(id: "system", kind: .system, relativePath: "audio/system.wav"),
                AudioTrack(id: "microphone", kind: .microphone, relativePath: "audio/microphone.wav")
            ]
        )
        let folder = MeetingFolder(rootURL: root, metadata: metadata)
        try writeMetadata(metadata, to: folder.metadataURL)
        return folder
    }

    public func writeMetadata(_ metadata: MeetingMetadata, to url: URL) throws {
        let data = try encoder.encode(metadata)
        let temporaryURL = url.deletingLastPathComponent().appending(path: ".metadata.json.tmp")
        try data.write(to: temporaryURL, options: [.atomic])
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: temporaryURL, to: url)
    }

    public func readMetadata(at url: URL) throws -> MeetingMetadata {
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(MeetingMetadata.self, from: data)
        } catch {
            throw MeetingStoreError.malformedMetadata(url)
        }
    }

    public func scanMeetings(outputRoot: URL) throws -> [MeetingFolder] {
        guard fileManager.fileExists(atPath: outputRoot.path) else { return [] }
        let children = try fileManager.contentsOfDirectory(
            at: outputRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var meetings: [MeetingFolder] = []
        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let metadataURL = child.appending(path: "metadata.json", directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: metadataURL.path) else { continue }
            do {
                let metadata = try readMetadata(at: metadataURL)
                meetings.append(MeetingFolder(rootURL: child, metadata: metadata))
            } catch MeetingStoreError.malformedMetadata {
                continue
            }
        }
        return meetings.sorted { $0.metadata.createdAt > $1.metadata.createdAt }
    }

    static func slug(for title: String, date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "Z", with: "Z")
        let cleanedTitle = title
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character == "-" && result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(timestamp)-\(cleanedTitle.isEmpty ? "meeting" : cleanedTitle)"
    }
}
