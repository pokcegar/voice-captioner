import Foundation

public enum TranscriptExporter {
    public static func markdown(meeting: MeetingMetadata, segments: [TranscriptSegment]) -> String {
        var lines: [String] = [
            "# \(meeting.title)",
            "",
            "- Created: \(ISO8601DateFormatter().string(from: meeting.createdAt))",
            "- Status: \(meeting.status.rawValue)",
            ""
        ]
        for segment in segments {
            let draft = segment.isDraft ? " draft" : ""
            lines.append("**[\(timestamp(segment.start)) - \(timestamp(segment.end))] \(segment.speakerLabel) (\(segment.sourceTrack.rawValue)\(draft))**")
            lines.append("")
            lines.append(segment.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func srt(segments: [TranscriptSegment]) -> String {
        segments.enumerated().map { index, segment in
            """
            \(index + 1)
            \(srtTimestamp(segment.start)) --> \(srtTimestamp(segment.end))
            \(segment.speakerLabel): \(segment.text)
            """
        }
        .joined(separator: "\n\n")
        + "\n"
    }

    public static func json(segments: [TranscriptSegment]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(segments)
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    static func srtTimestamp(_ seconds: TimeInterval) -> String {
        let totalMilliseconds = Int((seconds * 1_000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1_000
        let millis = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}
