import Foundation
import Testing
@testable import VoiceCaptionerCore

@Suite("Transcript")
struct TranscriptTests {
    @Test func mergesSegmentsByTimestampAndTrack() {
        let system = TranscriptSegment(
            id: "s1",
            sourceTrack: .system,
            speakerLabel: "Remote",
            start: 3,
            end: 4,
            text: "remote"
        )
        let microphone = TranscriptSegment(
            id: "m1",
            sourceTrack: .microphone,
            speakerLabel: "Local",
            start: 1,
            end: 2,
            text: "local"
        )

        let merged = TranscriptMerger.merge([[system], [microphone]])

        #expect(merged.map(\.id) == ["m1", "s1"])
    }

    @Test func finalSegmentsReplaceDraftsForSameTrack() {
        let draft = [
            TranscriptSegment(id: "d1", sourceTrack: .system, speakerLabel: "Remote", start: 0, end: 1, text: "draft", isDraft: true),
            TranscriptSegment(id: "d2", sourceTrack: .microphone, speakerLabel: "Local", start: 0, end: 1, text: "keep", isDraft: true)
        ]
        let final = [
            TranscriptSegment(id: "f1", sourceTrack: .system, speakerLabel: "Remote", start: 0, end: 1, text: "final", isDraft: false)
        ]

        let merged = TranscriptMerger.finalReplacingDrafts(draft: draft, final: final)

        #expect(merged.map(\.id) == ["d2", "f1"])
        #expect(merged.first { $0.id == "f1" }?.isDraft == false)
    }

    @Test func exportsMarkdownSRTAndJSON() throws {
        let meeting = MeetingMetadata(
            id: "meeting",
            title: "Planning",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            status: .complete
        )
        let segments = [
            TranscriptSegment(id: "1", sourceTrack: .system, speakerLabel: "Remote", start: 1.2, end: 3.4, text: "Hello")
        ]

        let markdown = TranscriptExporter.markdown(meeting: meeting, segments: segments)
        let srt = TranscriptExporter.srt(segments: segments)
        let json = try TranscriptExporter.json(segments: segments)

        #expect(markdown.contains("# Planning"))
        #expect(markdown.contains("Remote"))
        #expect(srt.contains("00:00:01,200 --> 00:00:03,400"))
        #expect(String(data: json, encoding: .utf8)?.contains("\"sourceTrack\" : \"system\"") == true)
    }
}
