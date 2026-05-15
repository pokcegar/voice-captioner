import SwiftUI
import VoiceCaptionerAppModel

struct MarkdownEditorPanel: View {
  @ObservedObject var viewModel: VoiceCaptionerAppModel

  private var strings: AppStrings { viewModel.strings }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(strings.text(.markdownEditor))
          .font(.headline)
        Spacer()
        Text(sourceLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        Button(strings.text(.saveEditedMarkdown)) {
          viewModel.saveEditableMarkdown()
        }
        .disabled(!viewModel.canSaveEditableMarkdown)
      }

      TextEditor(
        text: Binding(
          get: { viewModel.editableMarkdownText },
          set: { viewModel.updateEditableMarkdownText($0) }
        )
      )
      .font(.system(.body, design: .monospaced))
      .frame(minHeight: 220)
      .padding(6)
      .background(.background, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

      HStack {
        if viewModel.editableMarkdownText.isEmpty {
          Text(strings.text(.markdownWaitingForTranscript))
        } else if viewModel.isEditableMarkdownDirty {
          Text(strings.text(.unsavedChanges))
        } else if let status = viewModel.editableMarkdownStatus {
          Text(status)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var sourceLabel: String {
    switch viewModel.editableMarkdownSource {
    case .editedMarkdown: return strings.text(.markdownSourceEdited)
    case .finalMarkdown: return strings.text(.markdownSourceFinal)
    case .empty: return strings.text(.markdownWaitingForTranscript)
    }
  }
}
