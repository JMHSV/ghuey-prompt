import Testing
@testable import Ghuey_Prompt

struct PromptTitleTests {
    @Test func usesFirstNonEmptyLine() {
        #expect(PromptTitle.derive(from: "\n\n  Review this PR  \nDetails follow") == "Review this PR")
    }

    @Test func stripsMarkdownMarkers() {
        #expect(PromptTitle.derive(from: "## Code review checklist\n- item") == "Code review checklist")
        #expect(PromptTitle.derive(from: "- Be concise") == "Be concise")
    }

    @Test func truncatesLongLinesOnAWordBoundary() {
        let body = "You are a senior engineer reviewing a pull request for correctness, clarity, and test coverage"
        #expect(PromptTitle.derive(from: body) == "You are a senior engineer reviewing a pull request for…")
    }

    @Test func fallsBackForBlankText() {
        #expect(PromptTitle.derive(from: "  \n ") == "Untitled Prompt")
    }
}
