import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    var onPick: (ClipItem) -> Void
    var onClose: () -> Void
    var onOpenSettings: () -> Void

    @State private var query: String = ""
    @State private var selection: UUID?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            if filtered.isEmpty {
                emptyState
            } else {
                itemList
            }
            Divider().opacity(0.5)
            bottomBar
        }
        .frame(width: 400, height: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            searchFocused = true
            selection = filtered.first?.id
        }
    }

    private var filtered: [ClipItem] {
        store.search(query)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Buscar no histórico…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { pickSelected() }
                .onChange(of: query) { _ in
                    selection = filtered.first?.id
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - List

    private var itemList: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(filtered) { item in
                    ClipRow(item: item, isSelected: selection == item.id)
                        .tag(item.id)
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = item.id
                            onPick(item)
                        }
                        .contextMenu {
                            Button("Copiar") { onPick(item) }
                            Divider()
                            Button("Remover", role: .destructive) { store.delete(item) }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: selection) { id in
                if let id = id { proxy.scrollTo(id, anchor: .center) }
            }
            .background(
                KeyCaptureView(
                    onEnter: { pickSelected() },
                    onEscape: { onClose() },
                    onArrow: { move($0) }
                )
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 72, height: 72)
                Image(systemName: query.isEmpty ? "clipboard" : "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            Text(query.isEmpty ? "Histórico vazio" : "Nada encontrado")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "Copie algo para começar" : "Tente um termo diferente")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "tray.full")
                    .font(.system(size: 10, weight: .medium))
                Text(query.isEmpty
                     ? "\(store.items.count) \(store.items.count == 1 ? "item" : "itens")"
                     : "\(filtered.count) / \(store.items.count)")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)

            Spacer()

            if !store.items.isEmpty {
                Button {
                    store.clearAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Limpar")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remover todos os itens")

                Color.secondary.opacity(0.25)
                    .frame(width: 1, height: 11)
            }

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Preferências")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func pickSelected() {
        guard let id = selection ?? filtered.first?.id,
              let item = filtered.first(where: { $0.id == id }) else { return }
        onPick(item)
    }

    private func move(_ direction: MoveDirection) {
        let list = filtered
        guard !list.isEmpty else { return }
        let currentIdx = list.firstIndex(where: { $0.id == selection }) ?? 0
        let next: Int
        switch direction {
        case .up:   next = max(0, currentIdx - 1)
        case .down: next = min(list.count - 1, currentIdx + 1)
        }
        selection = list[next].id
    }
}

// MARK: - Row

struct ClipRow: View {
    let item: ClipItem
    var isSelected: Bool = false
    @State private var isHovering = false
    @State private var showPreview = false
    @State private var loadedImage: NSImage? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            thumbnailView
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(2)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                metadataLine
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering && !isSelected
                      ? Color.primary.opacity(0.05)
                      : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if isHovering { showPreview = true }
                }
            } else {
                showPreview = false
            }
        }
        .popover(isPresented: $showPreview, arrowEdge: .trailing) {
            ClipPreview(item: item)
        }
        .onAppear {
            if item.kind == .image {
                DispatchQueue.global(qos: .utility).async {
                    let img = item.loadImage()
                    DispatchQueue.main.async { loadedImage = img }
                }
            }
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch item.kind {
                case .image:
                    if let img = loadedImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    } else {
                        iconBox("photo", color: .purple)
                    }
                case .link:
                    iconBox("link", color: .blue)
                case .file:
                    iconBox("doc.fill", color: .orange)
                case .text:
                    iconBox("text.alignleft", color: .gray)
                }
            }
        }
        .frame(width: 44, height: 44)
    }

    private func iconBox(_ name: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.18), color.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.20), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(color)
            )
    }

    // MARK: - Metadata

    private var metadataLine: some View {
        HStack(spacing: 4) {
            Image(systemName: kindIcon)
                .font(.system(size: 9, weight: .semibold))
            Text(kindLabel)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.3)
            dot
            Text(relative(item.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            if let extra = sizeHint {
                dot
                Text(extra)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(kindColor)
    }

    private var dot: some View {
        Circle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 2, height: 2)
    }

    /// Linha secundária com contexto extra (domínio, caminho do arquivo etc.).
    private var subtitle: String? {
        switch item.kind {
        case .link:
            guard let s = item.text,
                  let host = URL(string: s)?.host else { return nil }
            return host.replacingOccurrences(of: "www.", with: "")
        case .file:
            guard let s = item.text else { return nil }
            return (s as NSString).lastPathComponent
        default:
            return nil
        }
    }

    /// Pequena dica numérica no fim da linha de metadados.
    private var sizeHint: String? {
        switch item.kind {
        case .text:
            let count = (item.text ?? "").count
            guard count > 0 else { return nil }
            return count > 999 ? "\(count / 1000)k chars" : "\(count) chars"
        case .image:
            guard let img = loadedImage else { return nil }
            return "\(Int(img.size.width))×\(Int(img.size.height))"
        default:
            return nil
        }
    }

    private var kindIcon: String {
        switch item.kind {
        case .text:  return "text.alignleft"
        case .link:  return "link"
        case .image: return "photo"
        case .file:  return "doc"
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .text:  return "TEXTO"
        case .link:  return "LINK"
        case .image: return "IMAGEM"
        case .file:  return "ARQUIVO"
        }
    }

    private var kindColor: Color {
        switch item.kind {
        case .text:  return .gray
        case .link:  return .blue
        case .image: return .purple
        case .file:  return .orange
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview Popover

struct ClipPreview: View {
    let item: ClipItem
    @State private var loadedImage: NSImage? = nil

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                if let img = loadedImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 240)
                        .padding(8)
                } else {
                    ProgressView()
                        .frame(width: 120, height: 80)
                        .padding(8)
                }
            case .link:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Link", systemImage: "link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.text ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: 280)
            case .file:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Arquivo", systemImage: "doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.text ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: 280)
            case .text:
                ScrollView {
                    Text(item.text ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(width: 420, height: min(CGFloat((item.text ?? "").count / 4 + 80), 480))
            }
        }
        .onAppear {
            if item.kind == .image {
                DispatchQueue.global(qos: .userInitiated).async {
                    let img = item.loadImage()
                    DispatchQueue.main.async { loadedImage = img }
                }
            }
        }
    }
}

// MARK: - Keyboard navigation

enum MoveDirection { case up, down }

/// NSView embutida para capturar setas/enter/esc sem conflitar com o TextField.
struct KeyCaptureView: NSViewRepresentable {
    var onEnter: () -> Void
    var onEscape: () -> Void
    var onArrow: (MoveDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = KeyView()
        v.onEnter = onEnter
        v.onEscape = onEscape
        v.onArrow = onArrow
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var onEnter: (() -> Void)?
        var onEscape: (() -> Void)?
        var onArrow: ((MoveDirection) -> Void)?

        override var acceptsFirstResponder: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.window?.isKeyWindow == true else { return event }
                switch event.keyCode {
                case 36, 76: // return / enter
                    self.onEnter?(); return nil
                case 53: // esc
                    self.onEscape?(); return nil
                case 125: // down
                    self.onArrow?(.down); return nil
                case 126: // up
                    self.onArrow?(.up); return nil
                default: return event
                }
            }
        }
        private var monitor: Any?
        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }
}
