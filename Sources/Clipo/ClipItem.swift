import AppKit
import Foundation
import UniformTypeIdentifiers

/// Tipo lógico do item do clipboard.
enum ClipKind: String, Codable {
    case text
    case link
    case image
    case file
}

/// Item do histórico do clipboard.
struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipKind
    let createdAt: Date
    /// Texto ou URL como string (para text/link/file).
    let text: String?
    /// Caminho do arquivo PNG salvo em disco (para image).
    let imagePath: String?
    /// Hash para deduplicação.
    let hash: String

    var preview: String {
        switch kind {
        case .text, .link, .file:
            return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            return "🖼 Imagem"
        }
    }

    var displayTitle: String {
        let p = preview
        let oneLine = p.replacingOccurrences(of: "\n", with: " ")
        if oneLine.count > 80 { return String(oneLine.prefix(80)) + "…" }
        return oneLine.isEmpty ? "(vazio)" : oneLine
    }

    func loadImage() -> NSImage? {
        guard let path = imagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }
}
