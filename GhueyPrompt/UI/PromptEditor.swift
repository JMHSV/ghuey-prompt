import SwiftUI

struct PromptEditor: View {
    let model: ShelfModel
    var focus: FocusState<ShelfView.Field?>.Binding

    // Bindings tolerate the draft disappearing: SwiftUI may still read them
    // during the update in which saving or cancelling clears the draft.
    private var title: Binding<String> {
        Binding { model.draft?.title ?? "" } set: { model.draft?.title = $0 }
    }

    private var text: Binding<String> {
        Binding { model.draft?.body ?? "" } set: { model.draft?.body = $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(titlePlaceholder, text: title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .focused(focus, equals: .title)
                .padding(.horizontal, 16)
                .frame(height: 48)
            Divider().opacity(0.5)
            TextEditor(text: text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused(focus, equals: .body)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text("Write or paste your prompt…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
            Divider().opacity(0.5)
            HStack {
                Button(model.isDiscardArmed ? "Discard Changes" : "Cancel") { model.cancelEditing() }
                    .help("esc")
                Spacer()
                Button("Save") { model.saveDraft() }
                    .buttonStyle(.borderedProminent)
                    .help("⌘↩")
            }
            .controlSize(.regular)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    /// Shows the title that will be used if the field is left blank.
    private var titlePlaceholder: String {
        let body = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? "Title" : PromptTitle.derive(from: body)
    }
}
