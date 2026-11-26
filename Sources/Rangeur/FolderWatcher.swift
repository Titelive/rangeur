import Foundation

/// Surveille un dossier et appelle `onChange` dès que son contenu change
/// (fichier ajouté, renommé ou supprimé).
final class FolderWatcher {
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?

    @discardableResult
    func start(url: URL) -> Bool {
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.onChange?()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
