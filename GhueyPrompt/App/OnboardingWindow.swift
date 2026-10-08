import AppKit
import SwiftUI

/// A short welcome tour whose steps tick themselves off as you actually do them.
@MainActor
final class OnboardingWindow {
    @MainActor @Observable
    final class Progress {
        var hasOpenedShelf = false
        var isAccessibilityTrusted = Accessibility.isTrusted
        var hasSavedPrompt = false
    }

    let progress = Progress()
    private var window: NSWindow?
    private var trustPoll: Timer?
    private let promptCount: () -> Int
    private var initialCount = 0

    init(promptCount: @escaping () -> Int) {
        self.promptCount = promptCount
    }

    func show() {
        initialCount = promptCount()
        progress.hasSavedPrompt = false
        if window == nil {
            let hosting = NSHostingView(rootView: OnboardingView(progress: progress) { [weak self] in self?.finish() })
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.center()
            self.window = window
        }
        trustPoll?.invalidate()
        trustPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.progress.isAccessibilityTrusted = Accessibility.isTrusted }
        }
        // macOS may decline activation for an app launched in the background;
        // ordering front regardless keeps the tour from opening behind other windows.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func shelfDidOpen() { progress.hasOpenedShelf = true }

    func promptCountChanged(to count: Int) {
        if count > initialCount { progress.hasSavedPrompt = true }
    }

    private func finish() {
        AppSettings.hasCompletedOnboarding = true
        trustPoll?.invalidate()
        trustPoll = nil
        window?.close()
    }
}

private struct OnboardingView: View {
    let progress: OnboardingWindow.Progress
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                Text("Welcome to Ghuey Prompt")
                    .font(.system(size: 22, weight: .bold))
                Text("A shelf of your best prompts, one flick of the pointer away.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Step(
                    isDone: progress.hasOpenedShelf,
                    title: "Push the pointer into the left edge of the screen",
                    detail: "The shelf slides out. Or press ⌥⌘P. It never takes over your app."
                )
                Step(
                    isDone: progress.isAccessibilityTrusted,
                    title: "Allow Accessibility access",
                    detail: "So a click can type the prompt where your cursor is.",
                    action: progress.isAccessibilityTrusted ? nil : ("Allow…", { Accessibility.requestTrust() })
                )
                Step(
                    isDone: progress.hasSavedPrompt,
                    title: "Save something",
                    detail: "Select text anywhere and press ⇧⌥⌘P — or drag it onto the screen edge."
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Good to know")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Tip(keys: "⇧-click", text: "stack several prompts, then insert them together")
                Tip(keys: "⌥-click", text: "insert with your clipboard attached")
                Tip(keys: "{{name}}", text: "in a prompt asks you for that value when inserting")
                Tip(keys: "⌃⌥1–9", text: "insert a favorite from anywhere (⌘D to favorite)")
            }

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Step: View {
    let isDone: Bool
    let title: String
    let detail: String
    var action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isDone ? Color.green : Color.secondary.opacity(0.6))
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isDone)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let action {
                Button(action.0, action: action.1)
            }
        }
    }
}

private struct Tip: View {
    let keys: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(keys)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.08), in: .rect(cornerRadius: 5))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
