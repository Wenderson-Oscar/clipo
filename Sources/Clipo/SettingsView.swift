import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    private let maxItemsOptions = [50, 100, 200, 500, 1000]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: - Geral
                sectionHeader("Geral")
                settingsGroup {
                    settingsRow {
                        Text("Iniciar ao fazer login")
                        Spacer()
                        Toggle("", isOn: $prefs.launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    Divider().padding(.leading, 14)
                    settingsRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Colar automaticamente")
                            Text("Envia ⌘V no app em foco ao selecionar um item")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $prefs.autoPaste)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    Divider().padding(.leading, 14)
                    settingsRow {
                        Text("Máximo de itens no histórico")
                        Spacer()
                        Picker("", selection: $prefs.maxItems) {
                            ForEach(maxItemsOptions, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                }

                // MARK: - Screenshots
                sectionHeader("Screenshots")
                settingsGroup {
                    settingsRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screenshots direto no clipboard")
                            Text("Prints vão ao clipboard sem salvar arquivo no Desktop")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $prefs.screenshotMode)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                // MARK: - Atalhos
                sectionHeader("Atalhos")
                settingsGroup {
                    shortcutRow("Navegar na lista", keys: "↑  /  ↓")
                    Divider().padding(.leading, 14)
                    shortcutRow("Colar selecionado", keys: "↵ Enter")
                    Divider().padding(.leading, 14)
                    shortcutRow("Fechar", keys: "⎋ Esc")
                }

                // MARK: - Sobre
                sectionHeader("Sobre")
                settingsGroup {
                    settingsRow {
                        Text("Clipo")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                    Divider().padding(.leading, 14)
                    settingsRow {
                        Text("Criado com Swift + AppKit")
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 20)
            }
        }
        .frame(width: 360, height: 490)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Layout helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }

    private func settingsRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func shortcutRow(_ label: String, keys: String) -> some View {
        settingsRow {
            Text(label)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
