import Testing
@testable import Ghuey_Prompt

struct TitleGeneratorTests {
    @Test func stripsLabelsQuotesAndExtraLines() {
        #expect(TitleGenerator.sanitize("Title: \"Summarize Meeting Notes\".\nHope that helps!") == "Summarize Meeting Notes")
        #expect(TitleGenerator.sanitize("**Code Review Checklist**") == "Code Review Checklist")
    }

    @Test func rejectsEmptyOrRunawayReplies() {
        #expect(TitleGenerator.sanitize("  \n") == nil)
        #expect(TitleGenerator.sanitize(String(repeating: "word ", count: 30)) == nil)
    }
}
