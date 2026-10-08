import Foundation
import Testing
@testable import Ghuey_Prompt

struct PromptMergeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func keepsPromptsFromBothSidesAndTheNewerEditOfShared() {
        let id = UUID()
        var older = Prompt(id: id, title: "Old title", body: "Body", createdAt: now - 100, useCount: 3)
        older.lastUsedByApp = ["a": now - 50]
        var newer = older
        newer.title = "New title"
        newer.updatedAt = now
        newer.useCount = 1
        newer.lastUsedByApp = ["b": now - 10]
        let onlyHere = Prompt(title: "Here", body: "h")
        let onlyThere = Prompt(title: "There", body: "t")

        let merged = PromptMerge.merge([older, onlyHere], [newer, onlyThere])

        #expect(Set(merged.map(\.title)) == ["New title", "Here", "There"])
        let shared = merged.first { $0.id == id }
        #expect(shared?.useCount == 3)
        #expect(shared?.lastUsedByApp == ["a": now - 50, "b": now - 10])
    }

    @Test func theSameTextSavedOnBothMacsIsKeptOnce() {
        let mine = Prompt(title: "Mine", body: "Explain this")
        let theirs = Prompt(title: "Theirs", body: "Explain this")
        #expect(PromptMerge.merge([mine], [theirs]).map(\.title) == ["Mine"])
    }
}
