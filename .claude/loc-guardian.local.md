---
max_pure_loc: 300
---

# loc-guardian Extraction Rules — vreader (Swift / iOS)

When a Swift file exceeds the LOC limit, prefer these extraction targets in order.

## Swift / SwiftUI

- **`@Model`**** types and SwiftData entities** → keep in `vreader/Models/<Name>.swift`. Split related entities into separate files even if small.
- **PersistenceActor CRUD per feature** → `PersistenceActor+<Feature>.swift` extension files (e.g., `+Library.swift`, `+Highlights.swift`, `+Bookmarks.swift`).
- **Reader container view extensions** → `<Container>+<Concern>.swift` (e.g., `EPUBReaderContainerView+Highlights.swift`, `+Navigation.swift`, `+Sheets.swift`).
- **Coordinator subviews / action methods** → split off SwiftUI computed property `var fooSection: some View` into a dedicated `FooSection.swift` view struct.
- **Pure helper types** → adjacent `<Module>Types.swift` (e.g., `FoliateTypes.swift`).
- **Constants / configuration** → `<Module>Config.swift` or top of the file in a private extension.
- **Test helpers** → `vreaderTests/Helpers/<Name>.swift`.

## When NOT to extract

- Tightly-coupled state machines that depend on each other's private types — extracting causes more friction than it removes.
- Single-use utilities that won't be called from elsewhere.
- Test files where each test method is small but there are many of them — totals > 300 lines is fine for test files.

## Tests don't count toward LOC

The LOC limit applies to production code in `vreader/`. `vreaderTests/` files can grow as needed; comprehensive coverage matters more than file size there.

## Naming

- New view file: `PascalCase` matching the type name.
- New extension file: `<Type>+<Concern>.swift` (the `+` is the convention).
- New service: `vreader/Services/<Feature>/<Name>.swift`.

