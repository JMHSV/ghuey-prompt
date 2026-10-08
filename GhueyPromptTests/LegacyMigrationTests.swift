import Foundation
import Testing
@testable import Ghuey_Prompt

@MainActor
struct LegacyMigrationTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "LegacyMigrationTests-\(UUID().uuidString)")
    private var legacyFile: URL { root.appending(path: "Prompt Library/prompts.json") }
    private var newFile: URL { root.appending(path: "Ghuey Prompt/prompts.json") }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func bringsOverPromptsFromTheOldNameAndKeepsTheOriginal() throws {
        try write("old library", to: legacyFile)

        try LegacyMigration.copyLegacyLibrary(to: newFile)

        #expect(try String(contentsOf: newFile, encoding: .utf8) == "old library")
        #expect(try String(contentsOf: legacyFile, encoding: .utf8) == "old library")
    }

    @Test func neverOverwritesTheNewLibrary() throws {
        try write("old library", to: legacyFile)
        try write("new library", to: newFile)

        try LegacyMigration.copyLegacyLibrary(to: newFile)

        #expect(try String(contentsOf: newFile, encoding: .utf8) == "new library")
    }
}
