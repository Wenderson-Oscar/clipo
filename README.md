# Clipo

<p align="center">
  <img src="assets/logo.svg" width="120" alt="Clipo logo" />
</p>

<p align="center">
  <strong>A lightweight clipboard manager for macOS — built with Swift and AppKit.</strong>
</p>

Clipo lives in your menu bar and keeps a searchable history of everything you copy: text, links, images, and files. Its standout feature is **automatic screenshot capture** — every screenshot you take is instantly placed in your clipboard and saved to your history, ready to paste without any extra steps.

---

## Features

- **Menu bar app** — no Dock icon, always out of the way
- **Clipboard history** for text, links, images, and files — persisted across restarts in `~/Library/Application Support/Clipo`
- **Instant search** with keyboard navigation — find anything in your history as you type
- **SHA-256 deduplication** — no repeated entries, even if you copy the same thing multiple times
- **Auto-paste** — selecting an item automatically sends `⌘V` to the focused app
- **Screenshot auto-copy** — takes a screenshot with `⇧⌘3` / `⇧⌘4` and it's instantly in your clipboard and history, with no file on the Desktop
- **Cross-device sync via Tailscale** — copy on Mac A, paste on Mac B; works across every Mac on your tailnet
- **Configurable preferences** — history limit, auto-paste, launch at login, screenshot mode, sync

## Requirements

- macOS 13 Ventura or later
- Swift 5.9+ (Xcode 15 or the `swift` command-line tool)

## Build & Run

```bash
# Build, package, and install to /Applications/Clipo.app
./build-app.sh

# Open the app
open /Applications/Clipo.app
```

For development:

```bash
swift run -c release
```

## Permissions

For **auto-paste** (`⌘V`) to work, grant Clipo Accessibility access:

**System Settings → Privacy & Security → Accessibility → add Clipo**

Without this permission, the item is still copied to your clipboard — you just press `⌘V` yourself.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate the list |
| `↵ Enter` | Paste selected item |
| `⎋ Esc` | Close panel |
| Right-click menu bar icon | Preferences, clear history, quit |

## Cross-Device Sync (Tailscale)

Clipo can mirror your clipboard between every Mac on your [Tailscale](https://tailscale.com) network. Copy on one Mac, and the item shows up in the history of every other Mac signed into the same tailnet.

**How to enable:**

1. Install Tailscale on every Mac and sign them all into the same tailnet.
2. Install Clipo on each Mac.
3. Open **Preferences → Sincronização (Tailscale)** and toggle **Compartilhar entre dispositivos** on. Repeat on each Mac.
4. The peer list in Preferences shows all Macs on your tailnet — green dot means online and reachable.

**How it works:**

- Each Clipo runs a small HTTP server on port `47823`, bound to your Mac's tailnet IP (`100.x.y.z`).
- When you copy something, Clipo `POST`s the item to every online peer on the tailnet.
- Incoming items are added to the local history without re-broadcasting (no loops).
- Connections are accepted **only** from the Tailscale CGNAT range (`100.64.0.0/10`) — anything from outside the tailnet is dropped.
- All traffic is end-to-end encrypted by Tailscale (WireGuard).

**What gets synced:**

- Text and links — always
- Images (PNG) — toggleable, capped at 8 MB per item
- File paths — never (paths don't make sense across machines)

**Requirements:**

- Tailscale CLI binary at one of: `/Applications/Tailscale.app/Contents/MacOS/Tailscale`, `/usr/local/bin/tailscale`, or `/opt/homebrew/bin/tailscale`
- All devices signed into the same tailnet

**Mobile (iPhone/Android):**

Not supported yet — Clipo is macOS-only. iOS sandboxing also prevents reading the clipboard in the background, so a phone-side app would only sync when actively opened.

## How Screenshot Auto-Copy Works

Clipo sets macOS to route screenshots directly to the clipboard via:

```bash
defaults write com.apple.screencapture target clipboard
```

This means when you press `⇧⌘3` or `⇧⌘4`, macOS places the image straight into `NSPasteboard` — no file is written to the Desktop. Clipo's clipboard monitor picks it up within ~0.6 seconds, registers it in history, and it's ready to paste anywhere.

You can toggle this behavior in **Preferences** (gear icon in the panel footer, or right-click the menu bar icon).

## Project Structure

```
Sources/Clipo/
  Main.swift              # entry point
  AppDelegate.swift       # menu bar item, panel, orchestration
  ClipItem.swift          # data model
  HistoryStore.swift      # JSON persistence + image files on disk
  ClipboardMonitor.swift  # NSPasteboard polling (0.6s interval)
  ScreenshotWatcher.swift # NSMetadataQuery fallback watcher
  ScreenshotMode.swift    # manages the defaults write system setting
  HotkeyManager.swift     # global hotkey via Carbon
  HistoryView.swift       # SwiftUI list, search, keyboard nav
  SettingsView.swift      # preferences panel UI
  Preferences.swift       # UserDefaults-backed settings
  TailscaleSync.swift     # peer discovery, HTTP server/client, sync manager
```
