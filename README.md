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
- **Configurable preferences** — history limit, auto-paste, launch at login, screenshot mode

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
```
