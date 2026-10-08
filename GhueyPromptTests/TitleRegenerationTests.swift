import Foundation
import Testing
@testable import Ghuey_Prompt

@MainActor
struct TitleRegenerationTests {
    private let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "TitleRegenerationTests-\(UUID().uuidString).json")

    @Test func regeneratesFromTheLatestSavedBodyAndPersistsOnlyTheTitleChange() async throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Summarize meeting notes", title: "My old title")
        let original = try #require(store.prompts.first)
        var receivedBody: String?
        let model = ShelfModel(store: store) { body in
            receivedBody = body
            return "Translate Into Italian"
        }

        model.beginEditing(original)
        model.draft?.body = "Translate the following text into Italian."
        model.saveDraft()
        try store.setFavorite(id: original.id, true)
        try store.recordUse(id: original.id, in: "com.apple.TextEdit")
        let saved = try #require(store.prompts.first)

        await model.regenerateTitle(for: original.id)

        #expect(receivedBody == "Translate the following text into Italian.")
        let regenerated = try #require(store.prompts.first)
        #expect(regenerated.title == "Translate Into Italian")
        #expect(regenerated.body == "Translate the following text into Italian.")
        #expect(regenerated.id == original.id)
        #expect(regenerated.createdAt == original.createdAt)
        #expect(regenerated.updatedAt >= saved.updatedAt)
        #expect(regenerated.favoritedAt == saved.favoritedAt)
        #expect(regenerated.useCount == saved.useCount)
        #expect(regenerated.lastUsedAt == saved.lastUsedAt)
        #expect(regenerated.lastUsedByApp == saved.lastUsedByApp)
        let reopened = try PromptStore(fileURL: fileURL)
        #expect(reopened.prompts.first?.title == "Translate Into Italian")
        #expect(reopened.prompts.first?.body == "Translate the following text into Italian.")
        #expect(model.generatingTitleIDs.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func preservesARenameMadeDuringGeneration() async throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Summarize meeting notes", title: "Original title")
        let prompt = try #require(store.prompts.first)
        let model = ShelfModel(store: store) { _ in
            try store.rename(id: prompt.id, to: "My manual title")
            return "Summarize Meeting Notes"
        }

        await model.regenerateTitle(for: prompt.id)

        #expect(store.prompts.first?.title == "My manual title")
        #expect(try PromptStore(fileURL: fileURL).prompts.first?.title == "My manual title")
        #expect(model.errorMessage == "The prompt changed while its title was being generated. Try again.")
        #expect(model.generatingTitleIDs.isEmpty)
    }

    @Test func discardsATitleForContentEditedDuringGeneration() async throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Summarize meeting notes", title: "Original title")
        let prompt = try #require(store.prompts.first)
        let model = ShelfModel(store: store) { _ in
            try store.update(id: prompt.id, title: prompt.title, body: "Translate into Italian")
            return "Summarize Meeting Notes"
        }

        await model.regenerateTitle(for: prompt.id)

        #expect(store.prompts.first?.title == "Original title")
        #expect(store.prompts.first?.body == "Translate into Italian")
        #expect(model.errorMessage != nil)
        #expect(model.generatingTitleIDs.isEmpty)
    }

    @Test func aDeletionDuringGenerationDoesNotRecreateThePrompt() async throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Summarize meeting notes")
        let prompt = try #require(store.prompts.first)
        let model = ShelfModel(store: store) { _ in
            try store.delete(id: prompt.id)
            return "Summarize Meeting Notes"
        }

        await model.regenerateTitle(for: prompt.id)

        #expect(store.prompts.isEmpty)
        #expect(try PromptStore(fileURL: fileURL).prompts.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(model.generatingTitleIDs.isEmpty)
    }

    @Test func anInFlightRequestBlocksDuplicatesButAllowsAnotherRegenerationAfterward() async throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Summarize meeting notes")
        let prompt = try #require(store.prompts.first)
        var calls = 0
        var model: ShelfModel!
        model = ShelfModel(store: store) { _ in
            calls += 1
            #expect(model.generatingTitleIDs == [prompt.id])
            await model.regenerateTitle(for: prompt.id)
            return calls == 1 ? "Summarize Meeting Notes" : "Extract Meeting Actions"
        }

        await model.regenerateTitle(for: prompt.id)
        #expect(calls == 1)
        #expect(store.prompts.first?.title == "Summarize Meeting Notes")
        #expect(model.generatingTitleIDs.isEmpty)

        await model.regenerateTitle(for: prompt.id)
        #expect(calls == 2)
        #expect(store.prompts.first?.title == "Extract Meeting Actions")
        #expect(model.generatingTitleIDs.isEmpty)
    }

    @Test(arguments: [TitleGenerator.GenerationError.unavailable, .invalidResponse])
    func generationFailurePreservesTheTitleAndAllowsRetry(_ error: TitleGenerator.GenerationError) async throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Summarize meeting notes", title: "My title")
        let prompt = try #require(store.prompts.first)
        var calls = 0
        let model = ShelfModel(store: store) { _ in
            calls += 1
            if calls == 1 { throw error }
            return "Summarize Meeting Notes"
        }

        await model.regenerateTitle(for: prompt.id)
        #expect(store.prompts.first?.title == "My title")
        #expect(model.errorMessage == error.localizedDescription)
        #expect(model.generatingTitleIDs.isEmpty)

        await model.regenerateTitle(for: prompt.id)
        #expect(store.prompts.first?.title == "Summarize Meeting Notes")
        #expect(model.errorMessage == nil)
        #expect(model.generatingTitleIDs.isEmpty)
    }

    @Test func aMissingPromptFailsBeforeInvokingTheGenerator() async throws {
        let store = try PromptStore(fileURL: fileURL)
        var calls = 0
        let model = ShelfModel(store: store) { _ in
            calls += 1
            return "Unexpected Title"
        }

        await model.regenerateTitle(for: UUID())

        #expect(calls == 0)
        #expect(model.errorMessage == StoreError.notFound.localizedDescription)
        #expect(model.generatingTitleIDs.isEmpty)
    }

    @Test func persistenceFailurePreservesTheSavedTitleAndSurfacesTheError() async throws {
        let store = try PromptStore(fileURL: fileURL)
        try store.save(text: "Summarize meeting notes", title: "My title")
        let prompt = try #require(store.prompts.first)
        let model = ShelfModel(store: store) { _ in
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
            return "Summarize Meeting Notes"
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await model.regenerateTitle(for: prompt.id)

        #expect(store.prompts.first?.title == "My title")
        #expect(model.errorMessage != nil)
        #expect(model.generatingTitleIDs.isEmpty)
    }
}
