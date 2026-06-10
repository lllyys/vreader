# Feature #97 — `list_library` AI agentic tool (enumerate the user's library)

> Status: PLANNED (Gate 1 drafted 2026-06-10). Size: **Small** (1 WI, 1 PR).
> User decision (2026-06-10): **"Tool only (require agentic)"** — add the tool to
> the agentic registry; enabling agentic tool-calling is the prerequisite. The
> default (non-agentic) chat experience is unchanged. NO flag-default flip, NO
> non-agentic intent-detection path.

## Problem

Asking the AI chat "what books are in my library?" (e.g. "library 里有哪些书?")
surfaces books *mentioned inside the current book's content* (Kahneman, van der
Kolk, …) prefixed "根据你提供的上下文" — it answers from the **chapter** context,
never the library. The agentic tool registry (feature #91) has
`search_current_book`, `search_other_books` (full-text search the whole library,
but **requires a query phrase**), and `get_book_content` (fetch a NAMED book) —
but **no enumerate/list tool**, so a list query ("what do I have?", no search
term) can't be answered. This feature adds the missing `list_library` tool.

Out of scope (per the user's "tool only" decision): the default-OFF `agenticTools`
gate stays OFF; the common "what's in my library" works only when the user has
turned agentic tool-calling on. The capability now *exists* (the feature title:
"AI chat **can** answer questions about the user's library"); making it the
default experience is a separate, verification-gated decision (#91's dark gate).

## Scope + WI split

| WI | Tier | Design | Status |
|----|------|--------|--------|
| **WI-1** — `ListLibraryTool` + registry registration + tests | behavioral (AI tool, no new UI chrome) | rule 51 N/A — the answer renders in the existing chat bubble (#86 Sources unchanged); no new surface | buildable now |

Single WI, single PR. The answer is text the model composes from the tool's
output, rendered in the existing chat bubble — **no new UI** (rule 51 N/A).

## Surface area (file-by-file)

### New

1. **`vreader/Services/AI/Tools/ListLibraryTool.swift`** — `struct ListLibraryTool: AITool`.
   Mirrors `SearchOtherBooksTool`'s shape (same `LibrarySearchBackend` dependency,
   same byte-clamp + coverage-footer idioms).
   ```swift
   struct ListLibraryTool: AITool {
       init(
           backend: any LibrarySearchBackend,
           currentBookFingerprintKey: String?,
           maxBooks: Int = 100,          // cap — never dump 500 titles into the prompt
           maxContentBytes: Int = 8_000  // byte budget (same clamp idiom as the peers)
       )
       var definition: ToolDefinition   // name: "list_library"
       func run(_ input: JSONValue) async -> ToolResult
   }
   ```
   - **Input schema** (all optional): `{ "include_current_book": bool (default true),
     "sort_by": enum["title","author","recent"] (default "recent"), "limit": integer }`.
   - **`run`**: `do { books = try await backend.libraryBooks() } catch` → `isError:
     true` with a short message (recoverable as data, never throws — the `AITool`
     contract). Then:
     - **empty library** → a clear "The library has no books." result (`isError: false`).
     - **dedupe by `fingerprintKey`** (defensive; the backend shouldn't return dupes
       but the tool must not double-count).
     - **exclude the open book** when `include_current_book == false` (match
       `currentBookFingerprintKey` against `item.fingerprintKey`).
     - **restore-placeholder titles** (Gate-2 Medium fix — bug #247 now passes a
       `titleOverride` at restore, so this is **legacy / defensive** cleanup of old
       rows, NOT a live path): a title matching `^restore_[0-9a-fA-F]{64}$` (the
       SHA-256 temp-file stem from `BookFileMaterializer`, **64** hex not 40) renders
       "(pending restore)" so the model never surfaces the internal id.
     - **format** — Gate-2 Medium fix: derive the format from
       `DocumentFingerprint(canonicalKey: item.fingerprintKey)?.format.rawValue`
       (the CANONICAL format, Bug #246 class), falling back to `item.format` only
       when the key is malformed. Do NOT trust the stale-prone `item.format` column
       directly.
     - **sort** per `sort_by` with EXPLICIT, total tie-breakers (Gate-2 Medium fix —
       `fetchAllLibraryBooks()` returns an unsorted array, so ties must be
       deterministic): `recent` = `lastReadAt` desc (nil last) → `addedAt` desc →
       `title` asc → `fingerprintKey` asc; `title` = `title` asc → `fingerprintKey`
       asc; `author` = `author` asc (nil last) → `title` asc → `fingerprintKey` asc.
     - **limit** — Gate-2 Medium fix: clamp the requested `limit` to `1...maxBooks`
       (a `limit <= 0` must NOT yield an empty list for a non-empty library; the
       peers clamp numeric input to ≥1). Effective cap = `min(max(1, limit ??
       maxBooks), maxBooks)`. If the (deduped, filtered) library is larger than the
       cap, append a one-line "Showing N of M books." note (NO silent truncation —
       rule 49; the model is told the list is partial).
     - **format-per-line** one compact line per book: `title — author · FORMAT[· NN%]`
       (progress only when present); CJK titles pass through (the byte-clamp counts
       UTF-8, never mid-scalar). Header line: total count + (when filtered) the
       active filter.
     - **byte-clamp** the whole payload to `maxContentBytes` via the existing
       `ToolResultText.clamp(_, toBytes:)` (Gate-2 Low fix — char-boundary +
       `…(truncated)` marker; the peers use this. NO new "whole-line" helper — that
       idiom does not exist, so the plan no longer claims it).

### Modified

2. **`vreader/Services/AI/Tools/AgenticToolRegistryBuilder.swift`** — append
   `ListLibraryTool(backend: libraryBackend, currentBookFingerprintKey:
   currentBook?.canonicalKey)` to the `tools` array in `build(...)` (after
   `SearchOtherBooksTool`, which shares the `libraryBackend`). No new dependency —
   `buildLive` already constructs `LibrarySearchBackendAdapter`, so the live
   registry gets `list_library` for free. No VM / driver / routing change (the
   agentic gate in `AIChatViewModel+Streaming.swift:140-151` already dispatches any
   registered tool).

3. **`vreader/Services/AI/AIChatAgenticSupport.swift`** — **Gate-2 High fix.** The
   agentic `systemPrompt()` currently says only "search the user's books and fetch
   book content" — it never mentions LISTING/enumerating, so the model may not
   discover it should call `list_library` for a "what's in my library" query
   (acceptance criterion 1 was "hopeful"). Add a clause so the prompt reads "…search
   the user's books, **list the books in their library,** and fetch book content."
   Minimal, instruction-only (the prompt's untrusted-data framing is unchanged).

4. **`vreader/Services/FeatureFlags.swift`** — **NO CHANGE** (per the user's "tool
   only" decision; `agenticTools` stays default-OFF).

### Files OUT of scope

- `FeatureFlags` default (no flip).
- `AIChatViewModel` / `AgenticChatDriver` / routing (the registry dispatch already
  handles any tool).
- Any new UI / Sources-chip change (rule 51 N/A — existing chat bubble).
- A non-agentic library-context path (the rejected alternative — user chose "tool only").
- `LibraryPersisting` (no new method — `fetchAllLibraryBooks()` already feeds the
  adapter's `libraryBooks()`).

## Prior art / project precedent / rejected alternatives

- **Precedent**: `SearchOtherBooksTool` (`Tools/SearchOtherBooksTool.swift`) — same
  `LibrarySearchBackend` dependency, same `currentBookFingerprintKey` exclusion,
  same byte-clamp + coverage-footer pattern. `ListLibraryTool` is its enumerate
  sibling (no query phrase, no FTS — just list).
- **Backend reuse**: `LibrarySearchBackend.libraryBooks() async throws ->
  [LibraryBookItem]` (`LibraryBookSearchGate.swift:94-95`,
  `LibrarySearchBackendAdapter.swift:54`) already returns the bookshelf. No new
  protocol/adapter.
- **Registry**: `AgenticToolRegistry` last-wins dedup + name-sorted `definitions()`
  (`AIToolRegistry.swift`) — registering a 4th tool is mechanical.
- **Rejected — flip `agenticTools` default-ON**: enables ALL agentic tools, a
  bigger surface #91 deliberately gated behind device verification. User chose not
  to (this PR).
- **Rejected — lightweight non-agentic intent-detection path**: would fix the
  default experience without agentic, but adds fuzzy "is this a library question?"
  detection + context injection that can misfire/noise. User chose not to.

## Test catalogue

**`vreaderTests/Services/AI/Tools/ListLibraryToolTests.swift`** (mirror
`SearchOtherBooksToolTests`'s `StubBackend` actor pattern + `LibraryBookItem.stub`):

- `definitionAdvertisesListLibrary` — `definition.name == "list_library"`, schema is
  a well-formed object with the optional params.
- `listsAllBooksWithTitleAuthorFormat` — happy path over a stub backend; each book's
  line carries title + author + format.
- `emptyLibraryReportsNoBooks` — empty `libraryBooks()` → clear non-error message.
- `excludesOpenBookWhenRequested` — `include_current_book=false` drops the
  `currentBookFingerprintKey` row; default keeps it.
- `dedupesByFingerprintKey` — duplicate rows collapse to one.
- `restorePlaceholderTitleIsFriendly` — a legacy `restore_<64hex>` title renders
  "(pending restore)", never the raw id; a normal title that merely *starts with*
  "restore" is untouched (anchored 64-hex regex).
- `sortByRecentTitleAuthorAreTotalAndDeterministic` — each `sort_by` orders
  correctly AND ties break deterministically (equal/nil dates, equal titles →
  fingerprintKey asc), so an unsorted input yields a stable list.
- `limitClampedToAtLeastOne` — `limit: 0` / negative does NOT empty a non-empty
  library (clamps to 1); `limit` above `maxBooks` clamps down.
- `capsLargeLibraryAndAnnouncesPartial` — > cap rows → capped list + "Showing N of
  M books." note (no silent truncation).
- `formatDerivedFromFingerprintNotStaleColumn` — a row whose `item.format` drifts
  from the canonical fingerprint format displays the CANONICAL format (Bug #246
  class); a malformed key falls back to `item.format`.
- `byteClampKeepsPayloadWithinBudget` — an over-budget payload is clamped via
  `ToolResultText.clamp` (char-boundary + `…(truncated)`), never mid-CJK-scalar.
- `backendThrowsYieldsRecoverableError` — `libraryBooks()` throws → `isError: true`,
  no crash.
- `cjkTitlesPassThrough` — CJK titles survive (byte-clamp counts UTF-8, not chars).

**`AgenticToolRegistryBuilderTests`** (extend): `build(...)` now includes
`list_library` in `definitions()` for both the open-book and general-chat cases.

**`AIChatAgenticSupportTests`** (extend, Gate-2 High fix): `systemPrompt()` mentions
listing/enumerating the library (so the model discovers `list_library`).

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| Large library blows the context window | `maxBooks` cap (100) + `maxContentBytes` (8 KB) byte-clamp + explicit "showing N of M" (no silent cap). |
| Restore-placeholder ids leak to the model/user (#247) | Map `restore_<hex>` → "(pending restore)". |
| Privacy — the list is the user's own data to their own provider | No cross-user surface; same trust boundary as `search_other_books` (which already enumerates `libraryBooks()`). The tool adds no NEW egress — it lists data the agentic path already exposes. |
| Tool throws and breaks the agentic loop | `AITool` contract: return `isError: true` as DATA, never throw (mirrors the peers). |
| CJK truncation mid-scalar | Byte-clamp trims whole lines (UTF-8 boundary), never mid-character. |

## Backward compat

Additive only. With `agenticTools` OFF (default) the registry isn't built into the
chat path, so behavior is unchanged. When agentic is ON, the model gains a 4th
read-only tool; existing tools/flows are untouched. No schema/persistence change.

## Acceptance criteria

1. With agentic tool-calling ON + a tool-use provider, asking "what books are in my
   library?" routes the model to `list_library` and the reply enumerates the actual
   library (titles/authors/format), NOT books mentioned in the current book.
2. Empty library → a clear "no books" answer.
3. Large library is capped + announced ("showing N of M"); the payload stays within
   the byte budget.
4. Restore-placeholder titles render friendly; CJK titles pass through; the open
   book is included by default and excludable.
5. The tool reports a recoverable error (never crashes the loop) if the backend throws.
6. With agentic OFF (default), behavior is unchanged (no regression).

## Revision history

- v1 (2026-06-10) — initial plan. Scope set by the user's "tool only (require
  agentic)" decision.
- v2 (2026-06-10) — Gate-2 Codex plan audit (`/tmp/feat97-planaudit.txt`): 1 High +
  4 Medium + 1 Low, all addressed:
  - **High** — the agentic `systemPrompt()` never mentions listing, so the model
    might not call `list_library` → added `AIChatAgenticSupport.swift` system-prompt
    update to the surface area + a test. Acceptance criterion 1 is now real, not
    hopeful.
  - **Medium** — restore placeholder is `restore_<64hex>` (SHA-256), not 40, and is
    now legacy/defensive (bug #247 passes `titleOverride`) → corrected.
  - **Medium** — `limit <= 0` would empty a non-empty library → clamp to `1...maxBooks`.
  - **Medium** — `item.format` is stale-prone (Bug #246 class) → derive from the
    canonical fingerprint, fall back to `item.format` only on a malformed key.
  - **Medium** — sort ties nondeterministic (unsorted source) → explicit total
    tie-breakers ending in `fingerprintKey asc`.
  - **Low** — no "whole-line" byte-clamp helper exists → use the existing
    `ToolResultText.clamp` (char-boundary); dropped the false claim.
  - Model-assumption verification PASSED: `AITool`/`ToolResult`/`JSONValue`/
    `LibrarySearchBackend.libraryBooks()`/`LibraryBookItem` fields/
    `AgenticToolRegistryBuilder` shape all confirmed against the codebase.
