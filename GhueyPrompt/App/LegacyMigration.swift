import Foundation

/// Carries prompts and settings over from when the app was called "Prompt Library".
/// Copies rather than moves, so the old files stay behind as a backup.
@MainActor
enum LegacyMigration {
    private static let legacyFolderName = "Prompt Library"
    private static let legacyDefaultsDomain = "com.homesetv.PromptLibrary"
    private static let settingKeys = ["revealOnScreenEdge", "edgeSensitivity", "libraryLocation", "hasCompletedOnboarding"]

    static func run() throws {
        migrateSettings()
        for location in [LibraryLocation.thisMac, .iCloudDrive] {
            try copyLegacyLibrary(to: location.fileURL)
        }
    }

    private static func migrateSettings() {
        let defaults = UserDefaults.standard
        guard let legacy = UserDefaults(suiteName: legacyDefaultsDomain) else { return }
        for key in settingKeys where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    /// Copies the old prompts file next to the new one, unless the new one already exists.
    static func copyLegacyLibrary(to fileURL: URL) throws {
        let manager = FileManager.default
        let legacyURL = fileURL.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: legacyFolderName, directoryHint: .isDirectory)
            .appending(path: fileURL.lastPathComponent)
        guard manager.fileExists(atPath: legacyURL.path), !manager.fileExists(atPath: fileURL.path) else { return }
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: legacyURL, to: fileURL)
    }
}
