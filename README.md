# Quick

**A native macOS launcher that lives in your menu bar. One hotkey, 24 built-in plugins, zero
third-party dependencies.**

<p align="center">
  <a href="https://github.com/ixxxxoooo/Quick/releases/latest">
    <img alt="Latest release"
         src="https://img.shields.io/github/v/release/ixxxxoooo/Quick?sort=semver&style=flat&label=release&color=1F6FEB"></a>
  <a href="https://github.com/ixxxxoooo/Quick/actions/workflows/ci.yml">
    <img alt="CI status"
         src="https://img.shields.io/github/actions/workflow/status/ixxxxoooo/Quick/ci.yml?branch=main&style=flat&label=CI"></a>
  <img alt="Swift 6.0"
       src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white">
  <img alt="macOS 26 or later"
       src="https://img.shields.io/badge/macOS-26%2B-000000?style=flat&logo=apple&logoColor=white">
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
</p>

Press **⌥Space** anywhere and a 750 × 475 palette drops in: launch an app, search files, paste from
clipboard history, do the math, translate offline, and reach ten developer tools — all without leaving
the keyboard.

SwiftUI and AppKit, **no Dock icon, no third-party dependencies, no telemetry**. Quick targets macOS 26
and nothing older, which is why it stays this small: no compatibility shims, no version switches, no
deprecated-API debt.

> Quick's interface is in Simplified Chinese.

## Features

**Everything under one hotkey**

- **App launcher** — fuzzy search over installed apps that also matches pinyin (full spelling or
  initials), ranked by how often you actually use them, with favorites pinned to the top.
- **File search** — `f ` / `file ` / `文件 ` searches filenames (and content) through Spotlight, with no
  index of Quick's own.
- **Clipboard history** — searchable text history, pinned entries, pasted back into the app you came
  from.
- **Calculator** — expressions evaluate inline as you type; a scratchpad keeps a persistent history.
- **Snippets** — reusable text templates, copied with `{date}` / `{clipboard}` / `{random}`
  placeholders expanded.
- **Notes and todos** — a lightweight two-tab panel, persisted in SQLite and searchable from the
  palette.
- **Translation** — fully offline: on-device translation, the system dictionary for single words, and
  system speech.
- **Calendar** — today's events in the panel; the palette previews the next few.

**System**

- **System control** — lock, sleep, restart, shut down, log out, empty the trash, eject disks, toggle
  appearance.
- **System monitor** — CPU, memory, disk and network at a glance.
- **Kill process** — sort processes by CPU or memory, filter by name, send SIGTERM or SIGKILL.
- **Screenshot** — freeze the screen, select and annotate in place, then save, copy or pin it.
- **OCR** — Vision text recognition over a screen region, with optional auto-copy.
- **Network tools** — LAN IP, optional public IP, and the DNS servers your resolver actually uses.

**AI**

- **AI aggregation** — DeepSeek, ChatGPT, Gemini, Claude, 豆包, Kimi, 智谱 and 通义千问 in one plugin,
  opened in Quick's own WebView windows. You stay signed in across restarts.

**Ten developer tools**

- JSON formatter (with a collapsible tree), SQL formatter, Base64 codec, URL codec, UUID generator,
  MD5/SHA-1/SHA-256/SHA-512, timestamp converter, side-by-side text diff, Markdown preview, and a color
  parser/comparer.

**Super Panel**

- **⌥C** — or press and hold the right mouse button, or middle-click — opens a second, smaller panel
  *at the cursor*. It reads the selection (falling back to the clipboard) and offers the actions that
  fit: open a URL, reveal a path in Finder, decode Base64, format JSON, translate. With nothing to act
  on, it becomes a workbench of your most-used tools.

## Install

Download the latest `Quick-*.dmg` from [Releases](https://github.com/ixxxxoooo/Quick/releases), open it,
and drag **Quick.app** onto **Applications**. macOS 26 or later, Apple silicon.

Quick is self-signed rather than notarized, so clear the quarantine flag once before the first launch:

```sh
xattr -dr com.apple.quarantine /Applications/Quick.app
```

The DMG ships `安装说明.txt` with that same line, ready to copy.

## Permissions

Quick asks for nothing up front. Each prompt appears the first time you use a feature that needs it,
and everything is granted in **System Settings → Privacy & Security**.

| Permission | What needs it |
| --- | --- |
| **Accessibility** | Pasting a result back into the app you came from, restoring focus, and system actions that drive other apps |
| **Screen Recording** | The screenshot tool and region OCR |
| **Input Monitoring** | Global hotkeys, on setups that don't deliver them otherwise |
| **Automation (Apple Events)** | System actions driven by AppleScript: appearance, sleep, restart, shut down, log out, empty trash, eject |

## Using it

1. **⌥Space** summons the palette and **Esc** dismisses it. Settings live behind the menu bar icon
   (**⌘,** in that menu); record a different hotkey under **Settings → Shortcuts**.
2. Type to filter. A plugin's own name is its trigger word, and some plugins claim a prefix: `f ` for
   files, `翻译 ` for translation.
3. **↑ / ↓** move through the results, **↵** runs the selected one.
4. **⌥C** opens the Super Panel at the cursor.

## Building from source

You need macOS 26+, Xcode 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
./Scripts/setup.sh       # once per clone — enables the versioned git hooks
./Scripts/run-tests.sh   # every package's tests; this is the hard gate
./Scripts/build.sh       # build .app
./Scripts/restart.sh     # build, kill the old instance, launch the new one
./Scripts/restart.sh --show   # same, and pop the palette on launch
```

`project.yml` is the single source of truth. `Quick.xcodeproj` is generated from it and **committed**,
so after editing `project.yml` run `xcodegen generate` and commit both sides. Debug builds are their own
channel — `Quick Dev.app`, with its own bundle id, preferences, TCC grants and log subsystem — so
developing never disturbs the copy you actually use.

**[docs/](docs/README.md)** indexes the rest: architecture, engineering standards, the design system,
the logging contract, and one document per plugin. **[AGENTS.md](AGENTS.md)** is the binding rulebook —
read it before changing anything structural.

## Contributing

Read **[AGENTS.md](AGENTS.md)** first. It is the authoritative rulebook, and it is enforced by hooks
rather than by good intentions:

- `./Scripts/run-tests.sh` must pass. The `pre-commit` hook runs it again and rejects the commit
  otherwise.
- Commit messages are English [Conventional Commits](https://www.conventionalcommits.org/); the
  `commit-msg` hook rejects anything else.
- **No third-party dependencies.** Confirm that no system framework can do it before proposing one.
- Every UI value comes from `DesignTokens`. A bare spacing, radius, size or color literal in a view is a
  defect, not a shortcut.
- Plugins reach each other only through `EventBus`, and only `AppCore` instantiates them.

If you're planning a change in behaviour rather than a fix, open an issue first so the approach can be
agreed on before you write the patch.

## License

[AGPL-3.0](LICENSE)
