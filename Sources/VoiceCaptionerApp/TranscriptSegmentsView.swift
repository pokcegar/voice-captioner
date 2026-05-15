import Foundation
import SwiftUI
import VoiceCaptionerAppModel

struct TranscriptSegmentsView: View {
  @ObservedObject var viewModel: VoiceCaptionerAppModel

  private var strings: AppStrings { viewModel.strings }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(strings.text(.transcriptPreview))
        .font(.headline)
      if viewModel.rollingPreview.isEmpty {
        Text(strings.text(.transcriptPreviewEmpty))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
      } else {
        ForEach(viewModel.rollingPreview, id: \.id) { segment in
          VStack(alignment: .leading, spacing: 6) {
            Text(
              "\(segment.speakerLabel) • \(segment.sourceTrack.rawValue) • \(format(segment.start))-\(format(segment.end))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(segment.text)
              .font(viewModel.isRecording ? .title3 : .body)
          }
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
      }
    }
  }

  private func format(_ seconds: TimeInterval) -> String {
    String(format: "%.1fs", seconds)
  }
}
