import Testing
@testable import Ghuey_Prompt

struct PromptTemplateTests {
    @Test func listsEachBlankOnceInOrderSkippingTheClipboard() {
        let body = "Translate {{ text }} into {{language}}. Keep {{text}} short. Context: {{Clipboard}}"
        #expect(PromptTemplate.fields(in: body) == ["text", "language"])
        #expect(PromptTemplate.usesClipboard(body))
    }

    @Test func fillsBlanksAndLeavesUnfilledOnesEmpty() {
        let rendered = PromptTemplate.render(
            "Write a {{tone}} reply to {{clipboard}} in {{language}}.",
            values: ["tone": "friendly"], clipboard: "their email"
        )
        #expect(rendered == "Write a friendly reply to their email in .")
    }

    @Test func attachesTheClipboardAsACodeBlockUnlessThePromptPlacesIt() {
        #expect(PromptTemplate.attachingClipboard("let x = 1\n", to: "Review this:")
            == "Review this:\n\n```\nlet x = 1\n```")
        #expect(PromptTemplate.attachingClipboard("ignored", to: "Fix {{clipboard}} now") == "Fix {{clipboard}} now")
    }

    @Test func singleBracesAreNotBlanks() {
        #expect(PromptTemplate.fields(in: "Return JSON like {\"a\": {b}}").isEmpty)
    }
}
