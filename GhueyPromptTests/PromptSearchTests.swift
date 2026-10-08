import Foundation
import Testing
@testable import Ghuey_Prompt

struct PromptSearchTests {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func emptyQueryListsMostRecentlyUsedFirst() {
        let oldButUsed = Prompt(title: "A", body: "a", createdAt: now - 10 * day, lastUsedAt: now)
        let newUnused = Prompt(title: "B", body: "b", createdAt: now - day)
        let oldUnused = Prompt(title: "C", body: "c", createdAt: now - 5 * day)

        let titles = PromptSearch.results(for: "  ", in: [oldUnused, newUnused, oldButUsed]).map(\.title)
        #expect(titles == ["A", "B", "C"])
    }

    @Test func requiresEveryWordSomewhereInTheTitleOrBody() {
        let review = Prompt(title: "Code review", body: "Check the diff for bugs")
        let refactor = Prompt(title: "Refactor", body: "Simplify this code")

        #expect(PromptSearch.results(for: "review bugs", in: [review, refactor]).map(\.title) == ["Code review"])
        #expect(PromptSearch.results(for: "review tests", in: [review, refactor]).isEmpty)
    }

    @Test func titleMatchesOutrankMoreRecentBodyMatches() {
        let bodyMatch = Prompt(title: "Refactor", body: "Write tests first", createdAt: now)
        let titleMatch = Prompt(title: "Tests for edge cases", body: "Cover boundaries", createdAt: now - 30 * day)

        let titles = PromptSearch.results(for: "tests", in: [bodyMatch, titleMatch]).map(\.title)
        #expect(titles == ["Tests for edge cases", "Refactor"])
    }

    @Test func ignoresCaseAndAccents() {
        let prompt = Prompt(title: "Résumé feedback", body: "…")
        #expect(PromptSearch.results(for: "RESUME", in: [prompt]).count == 1)
    }

    @Test func favoritesComeFirstInTheOrderTheyWereStarred() {
        let recent = Prompt(title: "Recent", body: "r", createdAt: now)
        let starredSecond = Prompt(title: "Second star", body: "s", createdAt: now - 9 * day, favoritedAt: now - day)
        let starredFirst = Prompt(title: "First star", body: "f", createdAt: now - 8 * day, favoritedAt: now - 2 * day)

        let titles = PromptSearch.results(for: "", in: [recent, starredSecond, starredFirst]).map(\.title)
        #expect(titles == ["First star", "Second star", "Recent"])
    }

    @Test func promptsUsedInTheCurrentAppComeFirst() {
        let usedInChatGPT = Prompt(title: "ChatGPT one", body: "c", createdAt: now - 9 * day,
                                   lastUsedAt: now - 3 * day, lastUsedByApp: ["com.openai.chat": now - 3 * day])
        let usedRecentlyElsewhere = Prompt(title: "Elsewhere", body: "e", createdAt: now - 9 * day,
                                           lastUsedAt: now, lastUsedByApp: ["com.apple.TextEdit": now])

        #expect(PromptSearch.results(for: "", in: [usedRecentlyElsewhere, usedInChatGPT], app: "com.openai.chat")
            .map(\.title) == ["ChatGPT one", "Elsewhere"])
        #expect(PromptSearch.results(for: "", in: [usedRecentlyElsewhere, usedInChatGPT], app: nil)
            .map(\.title) == ["Elsewhere", "ChatGPT one"])
    }

    @Test func findsEveryMatchForHighlighting() {
        let text = "Review the diff. Then réview again."
        let matches = PromptSearch.matchRanges(of: PromptSearch.terms(in: "REVIEW"), in: text).map { String(text[$0]) }
        #expect(matches == ["Review", "réview"])
    }
}
