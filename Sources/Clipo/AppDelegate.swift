import AppKit
import SwiftUI

// NSPanel que pode se tornar janela-chave sem ativar o app no Dock.
private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menuPanel: MenuPanel?
    private var settingsPanel: NSPanel?
    private let store = HistoryStore()
    private var clipMonitor: ClipboardMonitor!
    private var screenshotWatcher: ScreenshotWatcher!
    private var syncManager: TailscaleSyncManager!
    private var syncObservation: NSObjectProtocol?
    private var dismissMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipMonitor = ClipboardMonitor(store: store)
        clipMonitor.start()

        screenshotWatcher = ScreenshotWatcher(monitor: clipMonitor)
        screenshotWatcher.start()

        // Garante que screenshots vão direto ao clipboard desde o primeiro uso.
        if !Preferences.shared.screenshotMode {
            Preferences.shared.screenshotMode = true
        }

        syncManager = TailscaleSyncManager(store: store, monitor: clipMonitor)
        SyncCoordinator.shared.bind(syncManager)
        syncManager.start()
        syncObservation = NotificationCenter.default.addObserver(
            forName: .clipoSyncSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncManager.stop()
                self?.syncManager.start()
            }
        }

        setupStatusItem()
        buildPanel()
        buildSettingsPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipMonitor?.stop()
        screenshotWatcher?.stop()
        syncManager?.stop()
        if let obs = syncObservation {
            NotificationCenter.default.removeObserver(obs)
        }
        removeDismissMonitor()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        if let path = Bundle.main.path(forResource: "menubar", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.isTemplate = true
            button.image = img
        } else {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "Clipo")
            button.image?.isTemplate = true
        }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
            || (NSApp.currentEvent?.modifierFlags.contains(.control) ?? false)
        if isRight {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    // MARK: - Panel

    private func buildPanel() {
        let panel = MenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(
            rootView: HistoryView(
                store: store,
                onPick: { [weak self] item in self?.paste(item: item) },
                onClose: { [weak self] in self?.closePanel() },
                onOpenSettings: { [weak self] in self?.showSettingsPanel() }
            )
        )
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        menuPanel = panel
    }

    private func togglePanel() {
        guard let panel = menuPanel else { return }
        if panel.isVisible { closePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let panel = menuPanel,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // Posiciona o panel centralizado abaixo do botão da barra de menus.
        let btnScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let pw = panel.frame.width
        let ph = panel.frame.height
        var x = btnScreen.midX - pw / 2
        let y = btnScreen.minY - ph

        // Garante que não sai da tela horizontalmente.
        if let screen = button.window?.screen ?? NSScreen.main {
            x = max(screen.visibleFrame.minX,
                    min(x, screen.visibleFrame.maxX - pw))
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitor()
    }

    private func closePanel() {
        removeDismissMonitor()
        menuPanel?.orderOut(nil)
    }

    // MARK: - Dismiss ao clicar fora

    private func installDismissMonitor() {
        removeDismissMonitor()
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    private func removeDismissMonitor() {
        if let m = dismissMonitor { NSEvent.removeMonitor(m) }
        dismissMonitor = nil
    }

    // MARK: - Context menu (clique direito)

    private func showContextMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Abrir histórico",
                                  action: #selector(openPanel),
                                  keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let ssTitle = Preferences.shared.screenshotMode
            ? "✓ Screenshots → clipboard (ativo)"
            : "Screenshots → clipboard (inativo)"
        let ssItem = NSMenuItem(title: ssTitle,
                                action: #selector(toggleScreenshotMode),
                                keyEquivalent: "")
        ssItem.target = self
        menu.addItem(ssItem)

        let prefsItem = NSMenuItem(title: "Preferências…",
                                    action: #selector(openSettings),
                                    keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Limpar histórico",
                                   action: #selector(clearHistory),
                                   keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "Sobre Clipo",
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem(title: "Sair",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        if let button = statusItem.button {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: button.bounds.height + 4),
                       in: button)
        }
    }

    @objc private func openPanel() { showPanel() }
    @objc private func clearHistory() { store.clearAll() }
    @objc private func openSettings() { showSettingsPanel() }
    @objc private func toggleScreenshotMode() {
        Preferences.shared.screenshotMode.toggle()
    }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clipo"
        alert.informativeText = """
        Clipboard manager para macOS.
        • Histórico de textos, links, imagens e arquivos
        • Screenshots copiadas automaticamente para o clipboard
        """
        alert.runModal()
    }

    // MARK: - Settings Panel

    private func buildSettingsPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 620),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Preferências"
        panel.contentViewController = NSHostingController(rootView: SettingsView())
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        settingsPanel = panel
    }

    private func showSettingsPanel() {
        guard let panel = settingsPanel else { return }
        if !panel.isVisible { panel.center() }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Colar

    private func paste(item: ClipItem) {
        closePanel()
        store.moveToTop(item)

        switch item.kind {
        case .image:
            if let img = item.loadImage() { clipMonitor.copySilently(image: img) }
        case .file:
            if let path = item.text { clipMonitor.copySilently(fileURL: URL(fileURLWithPath: path)) }
        case .text, .link:
            if let t = item.text { clipMonitor.copySilently(text: t) }
        }
        if Preferences.shared.autoPaste {
            simulatePaste()
        }
    }

    private func simulatePaste() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            vDown?.post(tap: .cgAnnotatedSessionEventTap)
            vUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
