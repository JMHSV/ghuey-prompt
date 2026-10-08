import Foundation
import Testing
@testable import Ghuey_Prompt

@MainActor
struct PromptStoreTests {
    private let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "PromptStoreTests-\(UUID().uuidString)")
        .appending(path: "prompts.json")

    @Test func savedPromptsSurviveRelaunch() throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "  Explain this code step by step.\n", title: "Explain")
        try store.save(text: "Write tests first")

        let reopened = try PromptStore(fileURL: fileURL)
        #expect(reopened.prompts.map(\.title) == ["Explain", "Write tests first"])
        #expect(reopened.prompts.first?.body == "Explain this code step by step.")
    }

    @Test func savingTheSameTextTwiceKeepsOneCopy() throws {
        let store = try PromptStore(fileURL: fileURL)
        guard case let .created(original) = try store.save(text: "Summarize this") else {
            Issue.record("First save should create a prompt")
            return
        }
        #expect(try store.save(text: "Summarize this\n\n") == .alreadySaved(original))
        #expect(store.prompts.count == 1)
    }

    @Test func rejectsBlankText() throws {
        let store = try PromptStore(fileURL: fileURL)
        #expect(throws: StoreError.self) { try store.save(text: " \n ") }
        #expect(store.prompts.isEmpty)
    }

    @Test func editingWithABlankTitleDerivesOneFromTheBody() throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Old text", title: "Custom")
        let id = try #require(store.prompts.first?.id)

        try store.update(id: id, title: "  ", body: "# New heading\nMore")
        #expect(store.prompts.first?.title == "New heading")
    }

    @Test func usingAPromptIsRemembered() throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Translate to Italian")
        let id = try #require(store.prompts.first?.id)

        try store.recordUse(id: id, in: "com.openai.chat")
        try store.recordUse(id: id, in: nil)

        let reopened = try PromptStore(fileURL: fileURL)
        #expect(reopened.prompts.first?.useCount == 2)
        #expect(reopened.prompts.first?.lastUsedAt != nil)
        #expect(reopened.prompts.first?.lastUsedByApp.keys.sorted() == ["com.openai.chat"])
    }

    @Test func undoingADeletionPutsThePromptBackInPlace() throws {
        let store = try PromptStore(fileURL: fileURL)
        for text in ["One", "Two", "Three"] { try store.save(text: text) }
        let two = store.prompts[1]

        try store.delete(id: two.id)
        try store.restore(two, at: 1)

        #expect(try PromptStore(fileURL: fileURL).prompts.map(\.body) == ["One", "Two", "Three"])
    }

    @Test func generatedTitleNeverOverwritesARename() throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "summarize the following meeting notes into action items")
        let prompt = try #require(store.prompts.first)

        try store.rename(id: prompt.id, to: "Meeting actions")
        #expect(try store.applyGeneratedTitle("Summarize Meeting Notes", to: prompt) == false)
        #expect(store.prompts.first?.title == "Meeting actions")
    }

    @Test func picksUpEditsMadeByAnotherMac() throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Mine")

        let otherMac = try PromptStore(fileURL: fileURL)
        try otherMac.save(text: "Theirs")

        #expect(try store.reloadFromDisk())
        #expect(store.prompts.map(\.body) == ["Mine", "Theirs"])
        #expect(try store.reloadFromDisk() == false)
    }

    @Test func aVanishedFileDoesNotEmptyTheLibrary() throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Keep me")
        try FileManager.default.removeItem(at: fileURL)

        #expect(try store.reloadFromDisk() == false)
        #expect(store.prompts.map(\.body) == ["Keep me"])
    }

    @Test func movingTheLibraryMergesWithOneAlreadyThere() throws {
        let destination = fileURL.deletingLastPathComponent().appending(path: "cloud/prompts.json")
        let cloud = try PromptStore(fileURL: destination)
        try cloud.save(text: "From the other Mac")

        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "From this Mac")
        try store.relocate(to: destination)

        #expect(store.fileURL == destination)
        let reopened = try PromptStore(fileURL: destination)
        #expect(Set(reopened.prompts.map(\.body)) == ["From this Mac", "From the other Mac"])
        // The old file is left behind untouched, as a backup.
        #expect(try PromptStore(fileURL: fileURL).prompts.map(\.body) == ["From this Mac"])
    }

    @Test func unreadableFileFailsLoudlyAndIsLeftIntact() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        #expect(throws: (any Error).self) { try PromptStore(fileURL: fileURL) }
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "not json")
    }
}
