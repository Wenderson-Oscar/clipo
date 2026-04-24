import AppKit
import Foundation

/// Faz polling do NSPasteboard e registra novos itens.
@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private weak var store: HistoryStore?

    /// Marca que uma cópia foi feita por nós (para evitar loop).
    private var internalCopyChangeCount: Int = -1

    init(store: HistoryStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Copia texto para o clipboard sem registrar (reinserção via item existente).
    func copySilently(text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        internalCopyChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
    }

    func copySilently(image: NSImage) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        internalCopyChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
    }

    func copySilently(fileURL: URL) {
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        internalCopyChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
    }

    /// Copia uma imagem “de fora” (ex: screenshot do disco) e REGISTRA no histórico.
    func copyAndRegister(image: NSImage) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        lastChangeCount = pasteboard.changeCount
        store?.addImage(image)
    }

    private func tick() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        if current == internalCopyChangeCount { return }
        readCurrent()
    }

    private func readCurrent() {
        guard let store = store else { return }
        let types = pasteboard.types ?? []

        // Arquivos
        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            for url in urls {
                // Se for imagem no disco, trata como imagem
                if let img = NSImage(contentsOf: url),
                   ["png", "jpg", "jpeg", "gif", "tiff", "heic", "bmp"].contains(url.pathExtension.lowercased()) {
                    store.addImage(img)
                } else {
                    store.addFile(url)
                }
            }
            return
        }

        // Imagens
        if types.contains(where: { $0 == .tiff || $0 == .png }) ||
            NSImage.canInit(with: pasteboard) {
            if let image = NSImage(pasteboard: pasteboard) {
                store.addImage(image)
                return
            }
        }

        // Texto
        if let s = pasteboard.string(forType: .string) {
            store.addText(s)
        }
    }
}

private extension NSImage {
    static func canInit(with pb: NSPasteboard) -> Bool {
        pb.canReadObject(forClasses: [NSImage.self], options: nil)
    }
}
