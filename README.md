# AgentSweep

**English** · [简体中文](README.zh-CN.md)

A native macOS cleaner built only for AI coding agents.

**Website: [ai-suifeng.github.io/agent-clean-mac](https://ai-suifeng.github.io/agent-clean-mac/) · [Download](https://github.com/ai-suifeng/agent-clean-mac/releases/latest) · Free and open source**

Most developers now run several AI coding tools side by side: Claude Code, Codex, Cursor, Gemini, Kimi Code, MiniMax Code, ZCode, opencode and more. Each one quietly fills your home folder with session logs, SQLite databases, browser caches, npx/uv packages and leftovers from tools you already uninstalled. On a typical machine that adds up to **tens of gigabytes**.

General-purpose cleaners can tell you a folder is big. They can't tell you whether deleting it loses your chat history or logs you out. AgentSweep knows each tool's folder layout, explains every item in plain language and only touches what it can prove is safe.

![Results](docs/screenshots/results.jpg)

> The app UI is currently in Simplified Chinese. English localization is planned.

## Features

- **Scan**: every supported tool lights up on an orbit as it is scanned, and the data it finds streams into the counter in the middle.
- **Review**: a two-ring chart (tools inside, items outside) colored by risk. Hover for an explanation, click to toggle, or select and invert a whole group.
- **Clean**: selected items are moved to the Trash with a black-hole animation. Every clean is logged with the original paths so you can put things back.
- **Session history**: browse Claude Code and Codex sessions, including Codex's compressed `.jsonl.zst` files. Export them to Markdown before deleting.
- **Database compaction**: chat databases such as Cursor's `state.vscdb` are never deleted. AgentSweep backs them up, then runs `VACUUM`, and shows how much can actually be reclaimed.
- **Leftover detection**: finds data from tools whose app is gone (Trae, Windsurf, …).
- **Discovery**: lists folders that look like AI tools the rules don't cover yet. They are only shown, never cleaned.
- **Extensible rules**: add or override tools with a JSON file. No code changes or rebuild needed.
- **Updates itself**: checks GitHub once a day and installs signed updates through Sparkle. See [docs/RELEASING.md](docs/RELEASING.md).

| Scanning | Cleaning |
|---|---|
| ![Scanning](docs/screenshots/scanning.jpg) | ![Cleaning](docs/screenshots/cleaning.jpg) |
| **Session history** | **Database compaction** |
| ![Sessions](docs/screenshots/sessions.jpg) | ![Compaction](docs/screenshots/compact.jpg) |

## Supported tools

| Tool | What AgentSweep handles |
|---|---|
| Claude Code | old sessions (exportable), file-history snapshots, caches, logs, config backups |
| Codex (CLI + desktop) | old sessions incl. `.zst` (exportable), archived sessions, thread databases (compact), desktop and built-in browser caches, temp files |
| Cursor | chat database (compact only), stale workspace state, background-agent worktrees, caches, `.vsix` packages |
| Gemini / Antigravity | CLI checkpoints, caches, editor caches and workspace state |
| Kimi Code | sessions, query cache, logs, desktop caches |
| MiniMax Code | sessions, background tasks, runtime database (compact), caches |
| ZCode | session workdirs and artifacts, checkpoints, session database (compact), embedded-browser cache |
| DeepSeek Harness | sessions, desktop caches |
| opencode | session database (compact), snapshots, logs |
| Qwen Code, Kiro | sessions, caches, logs |
| Trae / TRAE SOLO, Windsurf | caches; all data once the app is uninstalled |
| Shared dev caches | `uv`, `npx`, `bun`, `pip` (most MCP servers are launched through these) |

## How it stays safe

Every rule has one of five risk levels:

| Level | Meaning | Default |
|---|---|---|
| Leftover | The tool's app is gone and its data remains | selected |
| Safe | Caches, logs, temp files that rebuild themselves | selected |
| Old history | Sessions untouched for 30 days; export first if you like | selected |
| Compact only | Databases. Never deleted, only backed up and `VACUUM`ed | locked |
| Protected | Credentials, config, skills, plugins, program files | locked |

- **Allow-list only.** Anything no rule matches is left alone. Paths matched by a protected rule, and every folder that contains one, can never be selected.
- **Guard rails.** Your home folder, `~/Library`, `~/.cache` and similar roots can never be removed whole, even if a rule is wrong.
- **Nothing is deleted outright.** Items go to the Trash and the clean is recorded in `~/Library/Application Support/AgentSweep/history/`.
- **Running tools.** AgentSweep warns before cleaning a tool that is running and refuses to compact a database while its app is open.

## Install

1. Download `AgentSweep.dmg` from the [website](https://ai-suifeng.github.io/agent-clean-mac/) or [Releases](https://github.com/ai-suifeng/agent-clean-mac/releases/latest).
2. Drag **AgentSweep** into **Applications**.
3. The build is not notarized yet, so macOS blocks the first launch. Right-click the app and choose **Open**, or run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/AgentSweep.app
   ```

Requires macOS 14 Sonoma or later. Runs natively on Apple silicon and Intel.

From 0.2.0 on, AgentSweep updates itself: it checks GitHub once a day, verifies the update's EdDSA signature and installs it in one click. Turn checks off, or install silently, in Settings (⌘,).

## Usage

1. **智能清理 (Clean)**: click **开始扫描** to scan. Review the findings, adjust the selection by item or by group, then click **清理** and confirm.
2. **会话历史 (Sessions)**: filter by tool, by age or by keyword. Select sessions, then **导出 Markdown** (export), **导出后移到废纸篓** (export and trash) or **移到废纸篓** (trash).
3. **数据库压缩 (Compact)**: quit the tool first, then click **压缩**. Backups are kept until you remove them.
4. **清理记录 (History)**: every clean, with a **恢复** (restore) button.
5. **规则库 (Rules)**: every rule, folders that look like uncovered tools, and the local rules folder.

**Disk space is freed only after you empty the Trash.** Until then, every clean can be restored.

**Restoring after a relaunch** may need Full Disk Access, because macOS guards the Trash. Without it, AgentSweep tells you which items to *Put Back* from Finder.

## Adding a tool

Drop a JSON file into `~/Library/Application Support/AgentSweep/rules.d/` and relaunch. A tool with the same `id` as a built-in one replaces it.

```json
{
  "tools": [
    {
      "id": "my-agent",
      "name": "My Agent",
      "color": "#22C55E",
      "detect": { "paths": ["~/.my-agent"], "apps": ["My Agent.app"], "processes": ["my-agent"] },
      "orphanWhenAppMissing": true,
      "rules": [
        { "id": "ma-protected", "label": "Config", "paths": ["~/.my-agent/config.json"], "risk": "protected", "action": "none", "explain": "Settings and login." },
        { "id": "ma-sessions", "label": "Old sessions", "paths": ["~/.my-agent/sessions/*"], "risk": "history", "action": "age-filter", "ageUnit": "entry", "explain": "Chat history." },
        { "id": "ma-cache", "label": "Cache", "paths": ["~/.my-agent/cache"], "risk": "safe", "action": "trash", "explain": "Rebuilt automatically." },
        { "id": "ma-orphan", "label": "Leftovers", "paths": ["~/.my-agent"], "risk": "orphan", "action": "trash", "onlyWhen": "appMissing", "explain": "The app is uninstalled." }
      ]
    }
  ]
}
```

- **Paths** support `~`, `*`, `?`, `{a,b}` and `**`.
- **`risk`**: `orphan`, `safe`, `history`, `compact` or `protected`.
- **`action`**: `trash`, `age-filter` (older than 30 days; `"ageUnit": "entry"` judges each matched folder as a whole), `vacuum` (SQLite) or `none`.

Contributions to the built-in [`rules.json`](Sources/AgentSweepCore/Resources/rules.json) are very welcome.

## Build from source

Requires Xcode 16 or later (Swift 5.10+).

```bash
git clone git@github.com:ai-suifeng/agent-clean-mac.git
cd agent-clean-mac
swift test                                  # core tests
scripts/build-app.sh --open                 # build/AgentSweep.app for this Mac
scripts/build-app.sh --universal --dist     # universal app + .zip + .dmg in build/
```

Pushing a tag like `v0.3.0` makes GitHub Actions build the universal `.dmg` and `.zip`, sign the update, write `appcast.xml` and attach everything to a release; installed apps pick it up within a day. The full process, keys and first-time setup are in [docs/RELEASING.md](docs/RELEASING.md).

### Development flags

```bash
open build/AgentSweep.app --args --scan                # start scanning on launch
open build/AgentSweep.app --args --section sessions    # open a page: clean / sessions / compact / history / rules
open build/AgentSweep.app --args --home /tmp/fake-home # treat another folder as the home folder
# Debug builds only (scripts/build-app.sh --debug): play the clean animation without moving any file
open build/AgentSweep.app --args --scan --demo-clean
```

## Project layout

| Path | Contents |
|---|---|
| `Sources/AgentSweepCore/Resources/rules.json` | Built-in rules |
| `Sources/AgentSweepCore/` | Glob matching, scanner, trash and restore, SQLite compaction, session export, discovery, process detection |
| `Sources/AgentSweep/` | SwiftUI app. `StageEngine.swift` draws the scanner, ring and black hole with `Canvas` + `TimelineView` |
| `scripts/` | App bundling, packaging and icon generation |
| `website/` | The website, deployed to GitHub Pages by `.github/workflows/pages.yml` |
| `video/` | Source of the intro films (shot list, renderer, score) |
| `docs/PRD.md` | Product requirements (Chinese) |
| `prototype/agentsweep.html` | Interactive HTML prototype of the UI |

## Known limitations

- The UI is Chinese only for now.
- Session export covers Claude Code and Codex. Cursor, Gemini, opencode and others are planned.
- Exporting Codex `.jsonl.zst` sessions needs `zstd` (`brew install zstd`).
- Cursor's chat database usually has little free space, so `VACUUM` reclaims little. Pruning old conversations is planned.
- Release builds are ad-hoc signed and not notarized yet.

## License

[MIT](LICENSE)
