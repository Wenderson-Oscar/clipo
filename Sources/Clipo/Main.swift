import AppKit
import SwiftUI

@main
struct ClipoMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // sem ícone no Dock
        app.run()
    }
}
