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

## License

TBD
