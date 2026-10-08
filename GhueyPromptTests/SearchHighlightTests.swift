import Testing
@testable import Ghuey_Prompt

struct SearchHighlightTests {
    @Test func excerptSkipsAFirstLineThatRepeatsTheTitle() {
        let prompt = Prompt(title: "Code review", body: "# Code review\nCheck correctness first.\n\nThen style.")
        #expect(SearchHighlight.excerpt(of: prompt, terms: []) == "Check correctness first. Then style.")
    }

    @Test func excerptJumpsToAMatchDeepInTheBody() {
        let filler = String(repeating: "lorem ipsum ", count: 20)
        let prompt = Prompt(title: "Long", body: filler + "the needle is here")

        let excerpt = SearchHighlight.excerpt(of: prompt, terms: PromptSearch.terms(in: "needle"))
        #expect(excerpt.hasPrefix("…"))
        #expect(excerpt.contains("the needle is here"))
        #expect(excerpt.count < 60)
    }
}
