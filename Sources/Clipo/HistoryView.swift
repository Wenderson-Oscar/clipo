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
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                itemList
            }
            Divider()
            bottomBar
        }
        .frame(width: 380, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Buscar no histórico…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
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
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - List

    private var itemList: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(filtered) { item in
                    ClipRow(item: item)
                        .tag(item.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
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
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 42, weight: .thin))
                .foregroundStyle(.quaternary)
            Text(query.isEmpty ? "Histórico vazio" : "Nada encontrado")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "Copie algo para começar" : "Tente um termo diferente")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text(query.isEmpty
                 ? "\(store.items.count) itens"
                 : "\(filtered.count) de \(store.items.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            if !store.items.isEmpty {
                Button {
                    store.clearAll()
                } label: {
                    Text("Limpar tudo")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Color.secondary.opacity(0.3)
                    .frame(width: 1, height: 12)
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
        .padding(.horizontal, 12)
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
    @State private var isHovering = false
    @State private var showPreview = false
    @State private var loadedImage: NSImage? = nil

    var body: some View {
        HStack(spacing: 10) {
            thumbnailView
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .lineLimit(2)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                HStack(spacing: 5) {
                    kindBadge
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Text(relative(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
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
        ZStack {
            switch item.kind {
            case .image:
                if let img = loadedImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                        )
                } else {
                    iconBox("photo", color: .purple)
                }
            case .link:
                iconBox("link", color: .blue)
            case .file:
                iconBox("doc", color: .orange)
            case .text:
                iconBox("doc.plaintext", color: Color(NSColor.secondaryLabelColor))
            }
        }
        .frame(width: 40, height: 40)
    }

    private func iconBox(_ name: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(color.opacity(0.12))
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 17))
                    .foregroundStyle(color)
            )
    }

    // MARK: - Kind Badge

    private var kindBadge: some View {
        Text(kindLabel)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(kindColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(kindColor.opacity(0.12))
            .clipShape(Capsule())
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
        case .text:  return Color(NSColor.secondaryLabelColor)
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
