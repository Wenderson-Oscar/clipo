import Foundation
import ServiceManagement

/// Configurações persistidas do Clipo via UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Keys {
        static let maxItems        = "maxItems"
        static let autoPaste       = "autoPaste"
        static let screenshotMode  = "screenshotMode"
        static let syncEnabled     = "syncEnabled"
        static let syncIncludeImages = "syncIncludeImages"
        static let deviceId        = "deviceId"
        static let deviceName      = "deviceName"
    }

    /// Número máximo de itens mantidos no histórico.
    @Published var maxItems: Int {
        didSet { UserDefaults.standard.set(maxItems, forKey: Keys.maxItems) }
    }

    /// Se verdadeiro, Clipo envia ⌘V automaticamente após colar um item.
    @Published var autoPaste: Bool {
        didSet { UserDefaults.standard.set(autoPaste, forKey: Keys.autoPaste) }
    }

    /// Se verdadeiro, screenshots vão direto ao clipboard (defaults write).
    @Published var screenshotMode: Bool {
        didSet {
            if screenshotMode { ScreenshotMode.enable() } else { ScreenshotMode.disable() }
        }
    }

    /// Iniciar Clipo ao fazer login.
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// Sincronização entre dispositivos via Tailscale.
    @Published var syncEnabled: Bool {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: Keys.syncEnabled) }
    }

    /// Inclui imagens (PNG) na sincronização. Pode ficar pesado.
    @Published var syncIncludeImages: Bool {
        didSet { UserDefaults.standard.set(syncIncludeImages, forKey: Keys.syncIncludeImages) }
    }

    /// Identificador único deste dispositivo (gerado uma vez).
    let deviceId: String

    /// Nome amigável do dispositivo (hostname).
    let deviceName: String

    /// Porta TCP usada pelo servidor de sincronização.
    let syncPort: UInt16 = 47823

    private init() {
        let storedMax = UserDefaults.standard.integer(forKey: Keys.maxItems)
        maxItems = storedMax > 0 ? storedMax : 500

        if UserDefaults.standard.object(forKey: Keys.autoPaste) != nil {
            autoPaste = UserDefaults.standard.bool(forKey: Keys.autoPaste)
        } else {
            autoPaste = true
        }

        // Reflete o estado atual do sistema sem chamar didSet
        screenshotMode = ScreenshotMode.isClipboardMode

        launchAtLogin = SMAppService.mainApp.status == .enabled

        // Sincronização
        syncEnabled = UserDefaults.standard.bool(forKey: Keys.syncEnabled)
        if UserDefaults.standard.object(forKey: Keys.syncIncludeImages) != nil {
            syncIncludeImages = UserDefaults.standard.bool(forKey: Keys.syncIncludeImages)
        } else {
            syncIncludeImages = true
        }

        if let id = UserDefaults.standard.string(forKey: Keys.deviceId), !id.isEmpty {
            deviceId = id
        } else {
            let id = UUID().uuidString
            deviceId = id
            UserDefaults.standard.set(id, forKey: Keys.deviceId)
        }

        if let name = UserDefaults.standard.string(forKey: Keys.deviceName), !name.isEmpty {
            deviceName = name
        } else {
            let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            deviceName = host
            UserDefaults.standard.set(host, forKey: Keys.deviceName)
        }
    }

    private func applyLaunchAtLogin() {
        Task {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                // Ignorado silenciosamente — requer bundle assinado e notarizado
            }
        }
    }
}
