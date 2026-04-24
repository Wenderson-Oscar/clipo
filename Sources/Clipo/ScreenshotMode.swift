import Foundation

/// Gerencia o modo de destino das screenshots do macOS:
/// - clipboard: imagem vai direto ao NSPasteboard (padrão Clipo)
/// - file:      imagem é salva em arquivo (padrão macOS)
enum ScreenshotMode {
    /// Retorna true se o macOS está configurado para enviar screenshots ao clipboard.
    static var isClipboardMode: Bool {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        return defaults?.string(forKey: "target") == "clipboard"
    }

    /// Ativa modo clipboard: screenshots vão direto ao NSPasteboard.
    static func enable() {
        setTarget("clipboard")
    }

    /// Desativa: screenshots voltam a ser salvas como arquivo (padrão do macOS).
    static func disable() {
        setTarget("file")
    }

    private static func setTarget(_ value: String) {
        // Escreve via defaults(1) para garantir que o domínio correto é atingido.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "com.apple.screencapture", "target", value]
        try? task.run()
        task.waitUntilExit()

        // Reinicia o SystemUIServer para a mudança ter efeito imediato.
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["SystemUIServer"]
        try? kill.run()
        kill.waitUntilExit()
    }
}
