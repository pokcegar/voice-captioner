import Foundation

public enum TranscriptMerger {
    public static func merge(_ segmentGroups: [[TranscriptSegment]]) -> [TranscriptSegment] {
        segmentGroups
            .flatMap { $0 }
            .sorted {
                if $0.start == $1.start {
                    return $0.sourceTrack.rawValue < $1.sourceTrack.rawValue
                }
                return $0.start < $1.start
            }
    }

    public static func finalReplacingDrafts(
        draft: [TranscriptSegment],
        final: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        let finalTracks = Set(final.map(\.sourceTrack))
        let retainedDrafts = draft.filter { !finalTracks.contains($0.sourceTrack) }
        return merge([retainedDrafts, final])
    }
}
