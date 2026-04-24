import Foundation
import ServiceManagement

/// Configurações persistidas do Clipo via UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Keys {
        static let maxItems      = "maxItems"
        static let autoPaste     = "autoPaste"
        static let screenshotMode = "screenshotMode"
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
