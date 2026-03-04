# VReader

An iOS reader app for EPUB, PDF, and plain text files — built with Swift 6, SwiftUI, and SwiftData.

## About

VReader is a modern reading app designed for iPhone and iPad (iOS 17+). It provides a unified reading experience across multiple document formats with features like bookmarks, highlights, full-text search, and reading time tracking. Documents sync across devices via iCloud.

## Features

- **Multi-format support** — Read EPUB, PDF, and TXT files in a single app
- **Bookmarks & highlights** — Save your place and annotate passages with color-coded highlights
- **Full-text search** — Search across your entire library with SQLite FTS5
- **Reading time tracking** — Automatic session tracking with per-book statistics and reading speed calculations
- **iCloud sync** — Library, bookmarks, highlights, and reading progress sync across devices via SwiftData + CloudKit
- **Import from anywhere** — Open files via Share Sheet, Files app, or direct download

## Tech Stack

| Component   | Technology                  |
| ----------- | --------------------------- |
| UI          | SwiftUI                     |
| Persistence | SwiftData + CloudKit        |
| EPUB        | Readium Swift Toolkit       |
| PDF         | PDFKit                      |
| TXT         | TextKit (UITextView bridge) |
| Search      | SQLite FTS5                 |
| Concurrency | Swift 6 strict concurrency  |
| Project gen | XcodeGen                    |

## Requirements

- iOS 17.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting Started

```bash
# Generate the Xcode project
xcodegen generate

# Open in Xcode
open vreader.xcodeproj
```

Then select a simulator or device and run.

## Project Structure

```
vreader/
├── App/             # App entry point
├── Models/          # SwiftData models
├── Views/           # SwiftUI views
├── ViewModels/      # View models
├── Services/        # Business logic, import, sync
└── Utils/           # Helpers and extensions
vreaderTests/        # Unit tests (Swift Testing)
vreaderUITests/      # UI tests (XCTest)
```

## AI-Powered Development

VReader is built using an AI-assisted coding workflow with multiple agents collaborating through structured processes.

### Tools

| Tool | Role |
|------|------|
| [Claude Code](https://claude.com/claude-code) | Primary coding agent — implementation, editing, code review, fixes |
| [Codex CLI](https://github.com/openai/codex) | Architecture review, auditing, autonomous implementation in sandbox |

### Workflow

The development process follows a gated, multi-agent pipeline:

1. **Plan** — Features are designed as detailed implementation plans with work items, acceptance criteria, and test requirements (`docs/codex-plans/`)
2. **Review** — Plans go through multi-round architecture review via Codex (consistency, completeness, feasibility, ambiguity, risk)
3. **Implement** — Work items are implemented by the implementer agent following TDD (RED-GREEN-REFACTOR)
4. **Audit** — Code is audited across 9 dimensions (correctness, security, duplication, dead code, performance, testing, etc.)
5. **Fix** — Audit findings are fixed and verified in iterative loops until clean
6. **Commit** — Changes are committed only on explicit request after passing all gates

### Agent Rules

Shared rules for all AI agents live in [`AGENTS.md`](AGENTS.md):

- **Test-first is mandatory** — Write a failing test before implementing any new behavior
- **Research before building** — Search for established patterns and proven solutions before inventing
- **Edge cases are not optional** — Brainstorm and test: empty input, null values, Unicode/CJK, concurrent access, network failures
- **Keep files under ~300 lines** — Split proactively to maintain readability
- **Keep diffs focused** — No drive-by refactors; only change what's needed

### Configuration

- `.claude/rules/` — Rule files for TDD, UI consistency, design tokens, keyboard shortcuts, version bumping
- `.claude/skills/` — Custom skill definitions (plan-audit, etc.)
- `CLAUDE.md` — Claude Code project instructions
- `AGENTS.md` — Shared instructions for all AI coding agents

## License

TBD
