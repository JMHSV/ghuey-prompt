import SwiftUI

struct ShelfView: View {
    @Bindable var model: ShelfModel
    @FocusState private var focus: Field?
    @State private var isDropTargeted = false
    /// Drives the cascade as cards appear.
    @State private var isRevealed = true

    enum Field: Hashable { case search, title, body }

    var body: some View {
        VStack(spacing: 0) {
            if model.draft != nil {
                PromptEditor(model: model, focus: $focus)
            } else if model.filling != nil {
                FillForm(model: model)
            } else {
                header
                Divider().opacity(0.5)
                content
                trays
            }
            statusLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.draft == nil) { _, isBrowsing in
            // Defer one runloop so the editor exists before it's focused.
            DispatchQueue.main.async { focus = isBrowsing ? nil : .body }
        }
        .onChange(of: model.searchFocusRequest) {
            DispatchQueue.main.async { if model.draft == nil { focus = .search } }
        }
        .onChange(of: model.presentationID) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { isRevealed = false }
            DispatchQueue.main.async { isRevealed = true }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focus, equals: .search)
            HeaderButton(symbol: "plus", help: "New Prompt (⌘N)") { model.beginEditing(nil) }
            HeaderButton(symbol: model.isPinned ? "pin.fill" : "pin", help: model.isPinned ? "Unpin" : "Keep Open") {
                model.actions.setPinned(!model.isPinned)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 48)
    }

    @ViewBuilder
    private var content: some View {
        let results = model.results
        Group {
            if model.store.prompts.isEmpty {
                EmptyShelfView()
            } else if results.isEmpty {
                Text("No prompts match “\(model.query)”")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cards(results)
            }
        }
        .overlay { if isDropTargeted { DropHighlight() } }
        .dropDestination(for: String.self) { texts, _ in
            texts.forEach(model.receiveDrop)
            return !texts.isEmpty
        } isTargeted: { isDropTargeted = $0 }
    }

    private func cards(_ results: [Prompt]) -> some View {
        let favoriteNumbers = Dictionary(
            uniqueKeysWithValues: model.favorites.prefix(9).enumerated().map { ($1.id, $0 + 1) }
        )
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, prompt in
                        PromptCard(
                            prompt: prompt,
                            model: model,
                            isKeyboardSelected: focus == .search && prompt.id == model.selected?.id,
                            favoriteNumber: favoriteNumbers[prompt.id]
                        )
                        .id(prompt.id)
                        .modifier(Cascade(index: index, isRevealed: isRevealed))
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                    }
                }
                .padding(10)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: results.map(\.id))
            }
            .scrollIndicators(.never)
            .onChange(of: model.selectedID) { _, id in
                guard let id, focus == .search || id == model.recentlyAddedID else { return }
                withAnimation(.snappy) { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder
    private var trays: some View {
        Group {
            if let deletion = model.recentlyDeleted {
                Tray {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                    Text("Deleted “\(deletion.prompt.title)”")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Undo") { model.undoDeletion() }
                        .help("⌘Z")
                }
            } else if !model.stackedIDs.isEmpty {
                Tray {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("\(model.stackedIDs.count) stacked")
                    Spacer(minLength: 8)
                    Button("Clear") { model.stackedIDs = [] }
                    Button("Insert") { model.insertStack() }
                        .buttonStyle(.borderedProminent)
                        .help("↩")
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: model.recentlyDeleted?.prompt.id)
        .animation(.snappy(duration: 0.25), value: model.stackedIDs.isEmpty)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .modifier(StatusLineStyle())
        } else if model.draft == nil, model.filling == nil, !model.store.prompts.isEmpty {
            Text("Click to insert · ⇧ stack · ⌥ add clipboard")
                .foregroundStyle(.tertiary)
                .modifier(StatusLineStyle())
        }
    }
}

/// Cards slide in one after another when the shelf opens.
private struct Cascade: ViewModifier {
    let index: Int
    let isRevealed: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: isRevealed ? 0 : -18)
            .opacity(isRevealed ? 1 : 0)
            .animation(
                .spring(response: 0.42, dampingFraction: 0.78).delay(Double(min(index, 12)) * 0.022),
                value: isRevealed
            )
    }
}

private struct Tray<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .font(.system(size: 12))
            .controlSize(.small)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct StatusLineStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(isHovered ? 0.08 : 0), in: .rect(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
    }
}

private struct EmptyShelfView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Drop text here to save it")
                .font(.system(size: 14, weight: .semibold))
            Text("Or select text in any app and press ⇧⌥⌘P, or right-click → Services → Save to Ghuey Prompt.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 14))
            .overlay {
                Label("Drop to Save", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(8)
            .allowsHitTesting(false)
    }
}
