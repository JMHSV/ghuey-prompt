import Testing
@testable import Ghuey_Prompt

@MainActor
struct PromptPreviewPanelTests {
    @Test func previewGrowsToShowLongPrompts() {
        let short = Prompt(title: "Short", body: "One line.")
        let long = Prompt(title: "Long", body: String(repeating: "Review this diff as a senior engineer and point out bugs. ", count: 8))

        let shortHeight = PromptPreviewPanel.contentHeight(for: short)
        let longHeight = PromptPreviewPanel.contentHeight(for: long)
        // Title plus at least one line of 12.5pt body text and padding.
        #expect(shortHeight > 60)
        // Eight sentences wrap onto several more lines at the preview's width.
        #expect(longHeight > shortHeight + 60)
    }
}
