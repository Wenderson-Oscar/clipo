import AppKit
import Combine
import CryptoKit
import Foundation

/// Armazena e persiste o histórico de clipes.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let fileURL: URL
    private let imagesDir: URL
    private let queue = DispatchQueue(label: "clipo.history.io", qos: .utility)

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Clipo", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("history.json")
        self.imagesDir = base.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Inserção

    /// Adiciona um item a partir de texto.
    func addText(_ string: String) {
        let trimmed = string
        guard !trimmed.isEmpty else { return }
        let kind: ClipKind = isLink(trimmed) ? .link : .text
        let h = Self.sha256("t:" + trimmed)
        insert(ClipItem(id: UUID(), kind: kind, createdAt: Date(),
                        text: trimmed, imagePath: nil, hash: h))
    }

    /// Adiciona um item de imagem.
    func addImage(_ image: NSImage) {
        guard let data = image.pngData() else { return }
        let h = Self.sha256Data(data)
        if items.first?.hash == h { return }
        let filename = "\(h.prefix(16))-\(Int(Date().timeIntervalSince1970)).png"
        let url = imagesDir.appendingPathComponent(filename)
        do {
            try data.write(to: url)
        } catch {
            NSLog("Clipo: falha ao salvar imagem: \(error)")
            return
        }
        insert(ClipItem(id: UUID(), kind: .image, createdAt: Date(),
                        text: nil, imagePath: url.path, hash: h))
    }

    /// Adiciona uma referência de arquivo.
    func addFile(_ url: URL) {
        let h = Self.sha256("f:" + url.path)
        insert(ClipItem(id: UUID(), kind: .file, createdAt: Date(),
                        text: url.path, imagePath: nil, hash: h))
    }

    private func insert(_ item: ClipItem) {
        // Dedup: se o mais recente já tem o mesmo hash, ignora.
        if let first = items.first, first.hash == item.hash { return }
        // Remove duplicatas existentes do mesmo hash.
        items.removeAll { $0.hash == item.hash }
        items.insert(item, at: 0)
        trim()
        persist()
    }

    // MARK: - Ações

    func moveToTop(_ item: ClipItem) {
        guard items.first?.id != item.id else { return }
        items.removeAll { $0.id == item.id }
        var promoted = item
        promoted = ClipItem(id: item.id, kind: item.kind, createdAt: Date(),
                            text: item.text, imagePath: item.imagePath, hash: item.hash)
        items.insert(promoted, at: 0)
        persist()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        if let path = item.imagePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        persist()
    }

    func clearAll() {
        for item in items {
            if let path = item.imagePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        items.removeAll()
        persist()
    }

    func search(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { item in
            if let t = item.text, t.lowercased().contains(q) { return true }
            if item.kind == .image, "imagem".contains(q) || "image".contains(q) { return true }
            return false
        }
    }

    // MARK: - Persistência

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            self.items = decoded
        }
    }

    private func persist() {
        let snapshot = items
        let url = fileURL
        queue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("Clipo: falha ao salvar histórico: \(error)")
            }
        }
    }

    private func trim() {
        let limit = Preferences.shared.maxItems
        guard items.count > limit else { return }
        let removed = items.suffix(items.count - limit)
        for item in removed {
            if let path = item.imagePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        items = Array(items.prefix(limit))
    }

    // MARK: - Utils

    private func isLink(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.contains("://") || t.hasPrefix("www.") else { return false }
        guard !t.contains(" "), !t.contains("\n") else { return false }
        return URL(string: t) != nil
    }

    private static func sha256(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Data(_ d: Data) -> String {
        let digest = SHA256.hash(data: d)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = self.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
