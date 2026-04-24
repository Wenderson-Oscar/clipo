import AppKit
import Foundation

/// Detecta novos screenshots via NSMetadataQuery (Spotlight) usando o atributo
/// `kMDItemIsScreenCapture`, sem precisar de Full Disk Access.
@MainActor
final class ScreenshotWatcher {
    private weak var monitor: ClipboardMonitor?
    private var query: NSMetadataQuery?
    private var knownPaths: Set<String> = []

    var enabled: Bool = true

    init(monitor: ClipboardMonitor) {
        self.monitor = monitor
    }

    func start() {
        stop()
        let q = NSMetadataQuery()
        // kMDItemIsScreenCapture: macOS marca toda screenshot com este atributo.
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        // Busca na home do usuário (Desktop, Documents, pasta customizada).
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.notificationBatchingInterval = 0.3

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: q
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: q
        )

        q.start()
        self.query = q
    }

    func stop() {
        guard let q = query else { return }
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: q)
        q.stop()
        query = nil
    }

    /// Fase inicial: snapshot de tudo que já existe para não re-copiar ao abrir.
    @objc private func didFinishGathering(_ note: Notification) {
        guard let q = query else { return }
        q.disableUpdates()
        knownPaths = paths(in: q)
        q.enableUpdates()
    }

    /// Chamado quando o Spotlight detecta novos arquivos que batem no predicado.
    @objc private func didUpdate(_ note: Notification) {
        guard enabled, let q = query else { return }
        q.disableUpdates()
        let current = paths(in: q)
        let newOnes = current.subtracting(knownPaths)
        knownPaths = current
        q.enableUpdates()

        for path in newOnes {
            let url = URL(fileURLWithPath: path)
            waitForStableFile(url) { [weak self] in
                guard let self = self else { return }
                guard let image = NSImage(contentsOf: url) else { return }
                self.monitor?.copyAndRegister(image: image)
                NSSound(named: "Tink")?.play()
            }
        }
    }

    // MARK: - Helpers

    private func paths(in q: NSMetadataQuery) -> Set<String> {
        var result = Set<String>()
        for i in 0..<q.resultCount {
            if let item = q.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                result.insert(path)
            }
        }
        return result
    }

    /// Aguarda o arquivo parar de crescer (gravação concluída) antes de ler.
    private func waitForStableFile(_ url: URL, attempts: Int = 10, completion: @escaping () -> Void) {
        var lastSize: Int64 = -1
        var tries = 0
        func check() {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs?[.size] as? Int64 ?? 0
            if size > 0 && size == lastSize {
                completion()
                return
            }
            lastSize = size
            tries += 1
            if tries >= attempts { completion(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { check() }
        }
        check()
    }
}
