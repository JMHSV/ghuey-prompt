import SwiftUI

struct PromptCard: View {
    let prompt: Prompt
    let model: ShelfModel
    let isKeyboardSelected: Bool
    /// The ⌃⌥ number that inserts this favorite from anywhere, if any.
    let favoriteNumber: Int?
    @State private var isHovered = false
    @State private var frame: CGRect = .zero
    @State private var glow = false
    @FocusState private var isRenameFocused: Bool

    private var terms: [String] { PromptSearch.terms(in: model.query) }
    private var isFlashed: Bool { model.flashedIDs.contains(prompt.id) }
    private var isRenaming: Bool { model.renamingID == prompt.id }
    private var stackPosition: Int? { model.stackedIDs.firstIndex(of: prompt.id).map { $0 + 1 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleRow
            let excerpt = SearchHighlight.excerpt(of: prompt, terms: terms)
            if !excerpt.isEmpty {
                Text(SearchHighlight.text(excerpt, terms: terms))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .lineSpacing(1.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(background)
        .overlay(border)
        .scaleEffect(isFlashed ? 0.975 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: isFlashed)
        .contentShape(.rect(cornerRadius: 12))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onHover { hovering in
            isHovered = hovering
            model.actions.preview(hovering ? prompt : nil, frame)
        }
        .onTapGesture {
            guard !isRenaming else { return }
            model.actions.preview(nil, frame)
            model.activate(prompt, modifiers: NSEvent.modifierFlags)
        }
        .onDrag {
            model.actions.preview(nil, frame)
            model.draggedPromptID = prompt.id
            return NSItemProvider(object: prompt.body as NSString)
        }
        .contextMenu { menu }
        .onChange(of: model.recentlyAddedID == prompt.id, initial: true) { _, isNew in
            guard isNew else { return }
            glow = true
            withAnimation(.easeOut(duration: 1.6).delay(0.4)) { glow = false }
        }
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if isFlashed {
                Label("Inserted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity), removal: .opacity))
            } else if isRenaming {
                TextField("Title", text: Bindable(model).renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($isRenameFocused)
                    .onAppear { isRenameFocused = true }
                    .onChange(of: isRenameFocused) { _, focused in if !focused { model.commitRename() } }
            } else {
                if let stackPosition {
                    Text("\(stackPosition)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.accentColor, in: .circle)
                }
                Text(SearchHighlight.text(prompt.title, terms: terms))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !isFlashed && !isRenaming { accessories }
        }
        .animation(.snappy(duration: 0.22), value: isFlashed)
    }

    @ViewBuilder
    private var accessories: some View {
        if isHovered {
            Image(systemName: "arrow.turn.down.left")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
        } else if prompt.isFavorite {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                if let favoriteNumber {
                    Text("⌃⌥\(favoriteNumber)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var background: some View {
        let base = isKeyboardSelected ? 0.16 : isHovered ? 0.1 : 0.05
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(base))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(isFlashed ? 0.2 : glow ? 0.22 : stackPosition != nil ? 0.1 : 0))
            }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(isFlashed || glow ? 0.8 : stackPosition != nil ? 0.45 : 0), lineWidth: 1.5)
            .shadow(color: Color.accentColor.opacity(isFlashed || glow ? 0.6 : 0), radius: 8)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Insert") { model.use([prompt]) }
        Button("Insert with Clipboard") { model.use([prompt], withClipboard: true) }
        Button(stackPosition == nil ? "Add to Stack" : "Remove from Stack") { model.toggleStacked(prompt) }
        Button("Copy") { model.copy(prompt) }
        Divider()
        Button(prompt.isFavorite ? "Remove from Favorites" : "Add to Favorites") { model.toggleFavorite(prompt) }
        Button("Rename") { model.beginRenaming(prompt) }
        Button("Edit…") { model.beginEditing(prompt) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(prompt) }
    }
}
