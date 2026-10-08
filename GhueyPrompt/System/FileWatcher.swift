import Foundation

/// Calls back when files in a directory are added, replaced, or removed.
/// Watching the directory (not the file) survives atomic saves, which swap the file out.
@MainActor
final class FileWatcher {
    private let source: DispatchSourceFileSystemObject
    private var pendingChange: Task<Void, Never>?

    init(directory: URL, onChange: @escaping @MainActor () -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: directory.path]) }

        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setCancelHandler { close(descriptor) }
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                // Coalesce the burst of events a single save produces.
                self?.pendingChange?.cancel()
                self?.pendingChange = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    if !Task.isCancelled { onChange() }
                }
            }
        }
        source.resume()
    }

    func stop() {
        pendingChange?.cancel()
        source.cancel()
    }
}
