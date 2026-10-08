import AppKit
import Foundation
import Testing
@testable import Ghuey_Prompt

@MainActor
struct ShelfModelTests {
    @MainActor final class Recorder {
        var inserted: [String] = []
        var saved: [String] = []
        var clipboard: String?
        var focusRequests = 0
        var focusReleases = 0
        var dismissals = 0
    }

    private func makeModel(prompts: [String]) throws -> (ShelfModel, Recorder) {
        let url = FileManager.default.temporaryDirectory.appending(path: "ShelfModelTests-\(UUID().uuidString).json")
        let store = try PromptStore(fileURL: url)
        for text in prompts { try store.save(text: text) }
        let recorder = Recorder()
        let model = ShelfModel(store: store)
        var actions = ShelfModel.Actions.none
        actions.insertText = { text, _ in recorder.inserted.append(text) }
        actions.readClipboard = { recorder.clipboard }
        actions.save = { recorder.saved.append($0) }
        actions.takeFocus = { recorder.focusRequests += 1 }
        actions.releaseFocus = { recorder.focusReleases += 1 }
        actions.dismiss = { recorder.dismissals += 1 }
        model.actions = actions
        model.prepareForPresentation(app: nil)
        return (model, recorder)
    }

    private func prompt(_ body: String, in model: ShelfModel) throws -> Prompt {
        try #require(model.store.prompts.first { $0.body == body })
    }

    // MARK: Keyboard

    @Test func escapeClearsTheSearchBeforeDismissing() throws {
        let (model, recorder) = try makeModel(prompts: ["Alpha"])
        model.query = "alp"

        model.handle(.cancel)
        #expect(model.query.isEmpty)
        #expect(recorder.dismissals == 0)

        model.handle(.cancel)
        #expect(recorder.dismissals == 1)
    }

    @Test func returnInsertsTheHighlightedPrompt() throws {
        let (model, recorder) = try makeModel(prompts: ["Alpha", "Beta", "Gamma"])
        let order = model.results.map(\.body)

        model.handle(.moveDown)
        model.handle(.primary)
        #expect(recorder.inserted == [order[1]])
    }

    @Test func arrowKeysStopAtTheEnds() throws {
        let (model, _) = try makeModel(prompts: ["Alpha", "Beta"])
        let order = model.results.map(\.body)

        model.handle(.moveUp)
        #expect(model.selected?.body == order[0])
        model.handle(.moveDown)
        model.handle(.moveDown)
        #expect(model.selected?.body == order[1])
    }

    // MARK: Inserting

    @Test func usingAPromptDoesNotReorderTheOpenShelf() throws {
        let (model, _) = try makeModel(prompts: ["Alpha", "Beta", "Gamma"])
        let before = model.results.map(\.body)

        try model.store.recordUse(id: try prompt(before[2], in: model).id, in: nil)
        #expect(model.results.map(\.body) == before)

        model.settleOrder()
        #expect(model.results.first?.body == before[2])
    }

    @Test func newPromptsAppearOnTopRightAway() throws {
        let (model, _) = try makeModel(prompts: ["Alpha", "Beta"])
        try model.store.save(text: "Fresh")
        #expect(model.results.first?.body == "Fresh")
    }

    @Test func blanksAreAskedForBeforeInserting() throws {
        let (model, recorder) = try makeModel(prompts: ["Translate {{text}} into {{language}}"])

        model.handle(.primary)
        #expect(recorder.inserted.isEmpty)
        #expect(model.filling?.fields == ["text", "language"])
        #expect(recorder.focusRequests == 1)

        model.filling?.values = ["text": "ciao", "language": "English"]
        model.handle(.primary)
        #expect(recorder.inserted == ["Translate ciao into English"])
        #expect(model.filling == nil)
    }

    @Test func escapeAbandonsFillingWithoutInserting() throws {
        let (model, recorder) = try makeModel(prompts: ["Hello {{name}}"])
        model.handle(.primary)

        model.handle(.cancel)
        #expect(model.filling == nil)
        #expect(recorder.inserted.isEmpty)
    }

    @Test func optionClickAttachesTheClipboard() throws {
        let (model, recorder) = try makeModel(prompts: ["Review this:"])
        recorder.clipboard = "let x = 1"

        model.activate(try prompt("Review this:", in: model), modifiers: .option)
        #expect(recorder.inserted == ["Review this:\n\n```\nlet x = 1\n```"])
    }

    @Test func clipboardPromptsExplainAnEmptyClipboard() throws {
        let (model, recorder) = try makeModel(prompts: ["Fix {{clipboard}}"])
        recorder.clipboard = nil

        model.handle(.primary)
        #expect(recorder.inserted.isEmpty)
        #expect(model.errorMessage != nil)
    }

    @Test func shiftClickStacksPromptsThatInsertTogetherInClickOrder() throws {
        let (model, recorder) = try makeModel(prompts: ["First", "Second", "Third"])

        model.activate(try prompt("Third", in: model), modifiers: .shift)
        model.activate(try prompt("First", in: model), modifiers: .shift)
        #expect(recorder.inserted.isEmpty)

        model.handle(.primary)
        #expect(recorder.inserted == ["Third\n\nFirst"])
        #expect(model.stackedIDs.isEmpty)
    }

    // MARK: Deleting

    @Test func deletingIsInstantAndUndoable() throws {
        let (model, _) = try makeModel(prompts: ["Alpha", "Beta", "Gamma"])
        let order = model.results.map(\.body)
        model.handle(.moveDown)

        model.handle(.delete)
        #expect(model.results.map(\.body) == [order[0], order[2]])
        #expect(model.selected?.body == order[2])

        model.handle(.undo)
        #expect(model.results.map(\.body) == order)
        #expect(model.selected?.body == order[1])
    }

    @Test func undoWithNothingDeletedIsLeftToTheSearchField() throws {
        let (model, _) = try makeModel(prompts: ["Alpha"])
        #expect(model.handle(.undo) == false)
    }

    // MARK: Editing

    @Test func editingTakesFocusAndFinishingGivesItBack() throws {
        let (model, recorder) = try makeModel(prompts: [])
        model.handle(.newPrompt)
        #expect(recorder.focusRequests == 1)

        model.draft?.body = "Brand new prompt"
        model.handle(.secondary)
        #expect(model.draft == nil)
        #expect(recorder.focusReleases == 1)
        #expect(model.selected?.title == "Brand new prompt")
    }

    @Test func escapeOnUnsavedChangesWarnsBeforeDiscarding() throws {
        let (model, _) = try makeModel(prompts: [])
        model.handle(.newPrompt)
        model.draft?.body = "Half-written idea"

        model.handle(.cancel)
        #expect(model.draft != nil)
        #expect(model.isDiscardArmed)

        model.handle(.cancel)
        #expect(model.draft == nil)
        #expect(model.store.prompts.isEmpty)
    }

    @Test func draftSurvivesClosingAndReopening() throws {
        let (model, _) = try makeModel(prompts: [])
        model.handle(.newPrompt)
        model.draft?.body = "Keep me"

        model.handle(.close)
        model.prepareForPresentation(app: nil)
        #expect(model.draft?.body == "Keep me")
    }

    @Test func renamingKeepsTheBody() throws {
        let (model, _) = try makeModel(prompts: ["Some long prompt text"])
        model.beginRenaming(try prompt("Some long prompt text", in: model))
        model.renameText = "Short name"

        model.handle(.primary)
        #expect(model.renamingID == nil)
        #expect(model.store.prompts.map(\.title) == ["Short name"])
        #expect(model.store.prompts.map(\.body) == ["Some long prompt text"])
    }

    @Test func droppingTextSavesItUnlessItIsACardDraggedBackIn() throws {
        let (model, recorder) = try makeModel(prompts: ["Alpha"])
        model.draggedPromptID = model.store.prompts.first?.id

        model.receiveDrop("Alpha")
        model.receiveDrop("Something new")
        #expect(recorder.saved == ["Something new"])
    }
}
