import SwiftUI

/// Asks for the values of a prompt's `{{placeholders}}` before inserting it.
/// Tab moves between fields; ↩ inserts; esc cancels.
struct FillForm: View {
    let model: ShelfModel
    @FocusState private var focusedField: String?

    var body: some View {
        if let filling = model.filling {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "curlybraces")
                        .foregroundStyle(Color.accentColor)
                    Text(filling.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(filling.fields, id: \.self) { field in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(field)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                TextField(field, text: value(for: field), axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .lineLimit(1...6)
                                    .focused($focusedField, equals: field)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 9, style: .continuous))
                            }
                        }
                        preview(filling)
                    }
                    .padding(16)
                }
                .scrollIndicators(.never)

                Divider().opacity(0.5)
                HStack {
                    Button("Cancel") { model.cancelFilling() }
                        .help("esc")
                    Spacer()
                    Button("Insert") { model.completeFilling() }
                        .buttonStyle(.borderedProminent)
                        .help("↩")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onAppear {
                DispatchQueue.main.async { focusedField = filling.fields.first }
            }
        }
    }

    private func preview(_ filling: ShelfModel.Filling) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Preview")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(filling.renderedText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(12)
        }
        .padding(.top, 4)
    }

    private func value(for field: String) -> Binding<String> {
        Binding {
            model.filling?.values[field] ?? ""
        } set: {
            model.filling?.values[field] = $0
        }
    }
}
