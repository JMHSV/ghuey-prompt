import Foundation

/// User preferences, persisted in UserDefaults.
@MainActor
enum AppSettings {
    private static let defaults = UserDefaults.standard

    static var revealsOnScreenEdge: Bool {
        get { defaults.object(forKey: "revealOnScreenEdge") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "revealOnScreenEdge") }
    }

    static var edgeSensitivity: EdgeSensitivity {
        get { defaults.string(forKey: "edgeSensitivity").flatMap(EdgeSensitivity.init) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "edgeSensitivity") }
    }

    static var libraryLocation: LibraryLocation {
        get { defaults.string(forKey: "libraryLocation").flatMap(LibraryLocation.init) ?? .thisMac }
        set { defaults.set(newValue.rawValue, forKey: "libraryLocation") }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }
}

/// How long the pointer must rest on the screen edge before the shelf opens.
enum EdgeSensitivity: String, CaseIterable {
    case quick, normal, deliberate

    var dwell: Duration {
        switch self {
        case .quick: .milliseconds(60)
        case .normal: .milliseconds(200)
        case .deliberate: .milliseconds(500)
        }
    }

    var title: String {
        switch self {
        case .quick: "Quick"
        case .normal: "Normal"
        case .deliberate: "Deliberate"
        }
    }
}

enum LibraryLocation: String {
    case thisMac
    case iCloudDrive

    var fileURL: URL {
        let directory = switch self {
        case .thisMac: URL.applicationSupportDirectory
        case .iCloudDrive: Self.iCloudDriveRoot
        }
        return directory.appending(path: "Ghuey Prompt", directoryHint: .isDirectory).appending(path: "prompts.json")
    }

    static var isICloudDriveAvailable: Bool {
        FileManager.default.fileExists(atPath: iCloudDriveRoot.path)
    }

    private static var iCloudDriveRoot: URL {
        URL.homeDirectory.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
    }
}
