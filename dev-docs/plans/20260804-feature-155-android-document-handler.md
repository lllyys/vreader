# Feature #155 — Android open-with / system document handler

- **Tracker row**: `docs/features.md:208` (box **G5**, parity phase 4, priority Medium)
- **Platform**: `android-app` (rule 40 → `android/version.properties`, tags `android/vX.Y.Z`)
- **iOS parity**: feature #59 (`docs/features.md:117`, GH #667, `VERIFIED`)
- **Design blocker filed**: `needs-design` **#2030** (§7)
- **Status**: Gate 1 complete; Gate 2 — see §14

---

## 1. Problem

`android/app/src/main/AndroidManifest.xml:19-24` declares exactly one intent-filter — `MAIN` +
`LAUNCHER` on `MainActivity`. Every other activity is `android:exported="false"`
(`:29,36,41,44`). The only exported-capable data component, `BookFileProvider`, is
`android:exported="false"` (`:53`) and outbound-only (feature #134 share).

Consequences for a user:

- VReader never appears in Android's **"Open with"** chooser for a `.epub` in Files, Downloads, or
  Drive.
- VReader never appears as a **share target** from Gmail, Telegram, a browser download, or another
  reader.
- The only way a book enters the library is the in-app SAF picker (`MainActivity.kt:62-64,108-112` →
  `LibraryViewModel.import`, `LibraryViewModel.kt:168`).

iOS has had this since #59: `project.yml:284-330` registers five `CFBundleDocumentTypes` plus Kindle
`UTImportedTypeDeclarations` with `LSSupportsOpeningDocumentsInPlace: true`, and
`VReaderApp.swift:466-491` routes the incoming URL to `FileURLImportRouter`.

**This feature IS an entry point**, which makes rule 47:90 ("Production reachability") unusually
load-bearing: the deliverable is precisely "a path a real user can take from outside the app" (§8).

---

## 2. Verified facts about the existing code

Every claim was checked at the cited line. Wiring claims are called out explicitly because rule 47:32
makes an unverified one a **High** finding.

| # | Claim | Evidence |
|---|---|---|
| F1 | Only `MAIN`/`LAUNCHER`; no `VIEW`, no `SEND`, no `<data>` in **any** merged manifest (`app/src/main` and `app/src/debug` both checked). | `android/app/src/main/AndroidManifest.xml:19-24`; `app/src/debug/AndroidManifest.xml` has no filter |
| F2 | `BookImporter.importStream(sourceUri, displayName, input, expectedKey)` is the stream-in/Book-out seam. | `.../data/BookImporter.kt:54-59` |
| F3 | Format derives **only** from the display-name extension; unknown throws before any write. | `BookImporter.kt:64-65` |
| F4 | Canonical key is `"$format:$sha256:$byteCount"` — **format participates in identity**. | `identity/.../Identity.kt:22-23`, used at `BookImporter.kt:75` |
| F5 | Dedup by that key ⇒ author-preserving **upsert**, not a second row. | `BookImporter.kt:85-107`; `LibraryRepository.kt:70` |
| F6 | Stored filename derives from the sanitized **key** (`[A-Za-z0-9._-]`), never the display name. | `BookImporter.kt:143-144`, used at `:87` |
| F7 | Failed/interrupted copy leaves no artifact: temp `.part` deleted in `finally`; promote is `ATOMIC_MOVE`. | `BookImporter.kt:117-120`, `:130-141` |
| F8 | DB failure after promote deletes the artifact only if freshly created. | `BookImporter.kt:108-115` |
| F9 | `titleFromDisplayName` = name minus last extension, blank-guarded. | `BookImporter.kt:146-147` |
| F10 | SAF path: `OpenableColumns.DISPLAY_NAME` → `uri.lastPathSegment` → literal `"book"`. | `LibraryViewModel.kt:174-176`, `:204-214` |
| F11 | Import failures already surface as a **shipped** `Toast` via `LibraryEvent.ImportFailed`; success is silent. | `LibraryViewModel.kt:62-63,164-165,185-189`; `MainActivity.kt:66-74` |
| F11b | That event bus is a **buffered `Channel`**, chosen precisely so an event during a collector gap is not dropped. | `LibraryViewModel.kt:161-165` (comment + `Channel(Channel.BUFFERED)`) |
| F12 | Book opening routes by typed `BookFormat` via `X.intent(context, key)`. | `MainActivity.kt:79-94`; `ReaderActivity.kt:1379-1380`, `TxtReaderActivity.kt:1371-1373`, `PdfReaderActivity.kt:289-291`, `Azw3ReaderActivity.kt:286-287` |
| F13 | Supported extensions: `epub`, `pdf`, `txt`, `md`/`markdown`, `azw3`/`azw`/`mobi`/`prc`. | `identity/.../DocumentFingerprint.kt:59-67` |
| F14 | `minSdk = 26`, `targetSdk = 36`, `compileSdk = 36`. | `android/app/build.gradle.kts:26,30,31` |
| F15 | **No activity declares a `launchMode`** — all default `standard`. | `grep -rn 'launchMode\|singleTask\|onNewIntent' app/src/main/` → 0 hits |
| F16 | Robolectric 4.13 available; `isIncludeAndroidResources = true`. | `android/app/build.gradle.kts:126`, `:50` |
| F17 | Foliate WebView hardened: `allowFileAccess=false`, `allowUniversalAccessFromFileURLs=false`, section scripts disabled. | `.../reader/foliate/FoliateBridge.kt:74-78` |
| F18 | `AppContainer` owns process-singleton `repository` + `importer`. | `VReaderApp.kt:67,70` |
| F19 | `scripts/run-android-tests.sh` **defaults to the `spikes/` harness**; the `:app` tasks require an explicit `ANDROID_CMD`. | `scripts/run-android-tests.sh:21-23,37-41` |
| F20 | `test-books/books/` holds **`azw3/`, `epub/`, `txt/` only** — there is **no real PDF and no real MD book**. | `ls test-books/books/` → 3 dirs; contents are 1 azw3, 2 epub, 1 txt |

**Wiring claim, stated precisely and verified.** The *in-app SAF* import entry point **is**
production-reachable: `LAUNCHER` → `MainActivity` (`AndroidManifest.xml:21-22`) → `LibraryScreen(onImport = …)`
(`MainActivity.kt:108-112`) → `rememberLauncherForActivityResult(OpenDocument())` (`:62-64`). The
*system document handler* entry point does **not exist at all** (F1) — that is the whole feature. No
claim anywhere in this plan asserts that any part of the open-with path is already wired.

**Correction to the tracker row.** `docs/features.md:208` cites `import-affordance-artboards.jsx` as
this feature's committed design. That file is **annotation** import (issue #963): its header says
"Sections mirror the three families in `vreader-annotation-import.jsx`" and its artboards sit on the
`HighlightsSheet` / `BookDetailsSheet`
(`dev-docs/designs/vreader-fidelity-v1/project/import-affordance-artboards.jsx:1-7,29,103,189`). It
depicts **no** book-file import state. `vreader-import-affordance.jsx` does not exist. See §7.

---

## 3. Decisions

### D1 — Post-import: **land in the Library; never auto-open the reader**

**Justification.** (1) iOS parity, read in code: `FileURLImportRouter.swift:63-66` imports and logs,
with only a `.bookDidImport` refresh (`BookImporter.swift:420-424` → `LibraryViewObservers.swift:61-63`);
#59's acceptance criterion (b) records "Library with the new row scrolled into view"
(`dev-docs/plans/20260515-feature-59-share-sheet-open-in-vreader.md:192`). Auto-opening would be a
*divergence*. (2) Inbound files are untrusted (rule 54) — import proves the bytes copied and hashed,
not that they parse; landing in the Library keeps a recoverable state on a parse failure. (3)
`SEND_MULTIPLE` has no defensible "which one?", so this is the only rule consistent across 1 and N.
(4) Rule 51 — the Library grid is a committed surface; auto-opening would need an undesigned Back
behaviour.

**Honest scope of (2).** D1 is *defence in depth*, not a security control: the bytes are already on
disk, and the user will very likely open the book next. Its real value is a recoverable failure mode
and consistency across batch sizes. It is not counted as a mitigation for any risk in §9.

**Rejected**: auto-open for the single-file case. Diverges from iOS, forks single/multi behaviour.

### D2 — A dedicated exported `ImportActivity`, with an explicit task model

Add `com.vreader.app.imports.ImportActivity`; `MainActivity` is untouched.

**Why not filters on `MainActivity`**: every activity is default `standard` (F15), so a `VIEW` filter
would stack a second `MainActivity` over an open reader; fixing that means changing app-wide launch
semantics. Least privilege (rule 54): exactly one small exported component. Trivially testable in
isolation.

**Task model — corrected at Gate-2 round 1 (H1).** When another app calls `startActivity` for our
activity *without* `FLAG_ACTIVITY_NEW_TASK`, the activity is placed in **the caller's task**, not
ours. So `ImportActivity` generally runs inside the sender's task, and a bare
`CLEAR_TOP|SINGLE_TOP` would target `MainActivity` **in the sender's task** — creating a new instance
rather than reusing ours. Corrected launch:

```kotlin
Intent(this, MainActivity::class.java).addFlags(
    Intent.FLAG_ACTIVITY_NEW_TASK or          // switch to VReader's own task (taskAffinity match)
    Intent.FLAG_ACTIVITY_CLEAR_TOP or         // reuse the existing MainActivity instance
    Intent.FLAG_ACTIVITY_SINGLE_TOP           // ...and do not recreate it if already on top
)
```

`ImportActivity` additionally declares `android:taskAffinity=""` and `android:excludeFromRecents="true"`
so it never pollutes VReader's task or Recents, and `android:noHistory="true"` so it cannot be
returned to. A connected warm-task test asserts exactly one `MainActivity` instance afterwards
(WI-5).

**Theme — corrected at round 1 (M2).** `Theme.NoDisplay` is **not** usable: a no-display activity must
finish before it would become visible, and this one must stay alive long enough to open the input
streams (D6). It uses a **translucent, non-`NoDisplay`** theme (`windowIsTranslucent=true`,
`windowBackground=@android:color/transparent`, `windowNoTitle=true`, `windowIsFloating=false`,
`backgroundDimEnabled=false`) — nothing is drawn, but the activity may live for as long as the stream
open takes.

**`CLEAR_TOP` finishing an open reader** is acceptable: positions persist continuously
(`LibraryRepository.kt:98`), and "Open with VReader" is an explicit request to be in VReader. The
alternative (finish without touching the task) is rejected because a successful import would then be
completely invisible.

### D3 — Format resolution: a fallback chain that never overrides a good extension

`IncomingBookResolver` resolves in order, stopping at the first success:

1. `OpenableColumns.DISPLAY_NAME` → `DocumentFingerprint.formatForFilename` (F13) — **identical to the
   SAF path** (F10), so the same file imported either way yields the same key.
2. `uri.lastPathSegment` extension → the same mapper.
3. `ContentResolver.getType(uri)` → the MIME map in D4. `application/octet-stream`, `*/*`, and `null`
   carry no information and map to nothing.
4. Magic-byte sniff (`BookMagicSniffer`, D7) over a mark-supporting stream, always rewound.
5. Otherwise → `ImportException.UnsupportedFormat`.

**Why 1–2 must beat 3–4 (identity stability).** Format is part of the canonical key (F4). If sniffing
could *override* an extension, a book already stored as `md:…` would return from an intent as `txt:…`
— a different key, a duplicate row, and a second copy on disk. Sniffing only ever fills a gap.

**Accepted limitations** (both Low, §13): a lying extension (`.txt` holding a PDF) still imports as
`txt`; and — per round 1 (H7) — a **nameless Markdown file** cannot be distinguished from plain text
by any magic bytes, so it resolves to `txt`. The sniffer therefore **never returns `md`**, and §12's
compatibility guarantee is explicitly scoped to extension-bearing inputs.

### D4 — MIME map, and `SEND` breadth (revised at round 1, H4)

Canonical map used by both the manifest filters and step 3 of D3:

| MIME | → format |
|---|---|
| `application/epub+zip`, `application/x-epub+zip`, `application/epub` | `epub` |
| `application/pdf`, `application/x-pdf` | `pdf` |
| `text/plain` | `txt` |
| `text/markdown`, `text/x-markdown` | `md` |
| `application/vnd.amazon.ebook`, `application/vnd.amazon.mobi8-ebook`, `application/x-mobipocket-ebook` | `azw3` |
| `application/octet-stream`, `*/*`, `null` | *(nothing — falls through)* |

**Round-1 correction.** v1 excluded `text/plain` and `application/octet-stream` from `SEND` to avoid
share-sheet noise. The auditor is right that this breaks the common real cases — sharing a `.txt`/`.md`
from a file manager, and sharing an EPUB/AZW3 that a provider types as `octet-stream` — and it
contradicted WI-6's own SEND acceptance. **Both are now accepted on `SEND` as well as `VIEW`**, with
the discrimination moved from the manifest to **runtime**:

`ImportActivity` treats a `SEND` intent that carries **no** `EXTRA_STREAM` and **no** `ClipData` URI
as "not a file share" — it finishes immediately without importing and without launching
`MainActivity`, returning the user to the sender. That is exactly the plain-text-snippet case, which
is the only thing the manifest exclusion was buying.

**Accepted cost** (§13): VReader appears in the share sheet for text snippets and arbitrary binaries.
Android's share sheet ranks by usage, so an unused entry sinks. The reachability this feature exists to
deliver outweighs a dismissible row.

**Still rejected**: `android:mimeType="*/*"` anywhere.

### D5 — Ship without the import-feedback surfaces; the blocker is filed

§7. Errors reuse the already-shipped `LibraryEvent.ImportFailed` toast verbatim (F11); success and
duplicate are silent, matching iOS. Tracked by `needs-design` **#2030**.

### D6 — Streams are opened **before** `ImportActivity` finishes (round 1, H2)

**The defect in v1.** `enqueue(uris: List<Uri>)` handed *URIs* to a process-scoped coordinator, so the
coordinator would call `openInputStream` *after* `ImportActivity` finished — by which time the
`FLAG_GRANT_READ_URI_PERMISSION` grant is gone. R3's "the open fd survives revocation" mitigation was
therefore not implemented by the proposed API.

**Corrected design.** `ImportActivity` resolves and opens every stream **while it is alive**, then
hands already-open work to the coordinator. Per round 2, two further corrections:

- **One stream, not two (r2 M1).** v2 had `resolve(uri)` sniff one stream and `openStream(uri)` open a
  second — a TOCTOU window, and a second open is not even guaranteed to succeed or return the same
  bytes on a one-shot provider. Replaced by a single **`resolveAndOpen(uri)`** that opens exactly one
  stream, sniffs through `mark`/`reset`, and returns that same rewound stream.
- **Per-URI failures must survive the handoff (r2 H3).** Resolution and opening happen in
  `ImportActivity`, but v2's coordinator accepted only *successful* items — so `Unsupported` and
  `Unreadable` had no route to `outcomes` and would never toast. The queue therefore carries a
  **per-URI envelope**, and the coordinator emits pre-resolved failures one-for-one on the same
  channel, preserving exactly one outcome per input URI:

```kotlin
data class PendingImport(
    val uri: Uri, val displayName: String, val format: BookFormat,
    /** uri.toString() ALREADY capped to MAX_SOURCE_URI_CHARS; this is the exact value the
     *  coordinator passes as importStream(sourceUri = …) — the cap's concrete data path (r3 M1). */
    val sourceUri: String,
    val declaredSize: Long?,          // OpenableColumns.SIZE, -1/absent → null
    val stream: InputStream,          // ALREADY OPEN, rewound — the fd outlives the grant
)

sealed interface IncomingItem {
    data class Ready(val pending: PendingImport) : IncomingItem
    /** Resolution/open already failed in ImportActivity; the coordinator just relays it. */
    data class PreResolved(val outcome: IncomingImportOutcome) : IncomingItem
}
fun enqueue(items: List<IncomingItem>)    // coordinator OWNS and closes every stream
```

Ownership is explicit: the coordinator closes every stream on every path — success, failure, timeout,
byte-cap abort, and items rejected by the in-flight cap.

`ImportActivity` does this on its **`lifecycleScope`** with the resolve/open on the IO dispatcher, and
calls `finish()` only after `enqueue` returns. This is why the theme cannot be `NoDisplay` (D2).

### D7 — Bounded, library-free EPUB sniffing (round 1, M3)

v1 said "parsing happens later", but sniffing an EPUB means reading attacker-controlled ZIP structure
at import time. The sniffer therefore uses **no ZIP library and never inflates anything**. Within the
4096-byte probe buffer only:

- `%PDF-` at offset 0 → `pdf`.
- `PK\x03\x04` at offset 0 → read the local-file-header fields **from the buffer only** (compression
  method @8, compressed size @18, uncompressed size @22, filename length @26, extra length @28);
  accept `epub` **only if** all of: the first entry is named exactly `mimetype`; it is **STORED**
  (method 0); **extra length == 0**; **compressed size == uncompressed size == 20**; and its 20
  content bytes equal `application/epub+zip`. These are the OCF requirements, and checking the size
  and extra-length fields (added at round 2, M5) is what stops a crafted header from steering the
  20-byte read. Anything else → `null`. A deflated or malformed first entry is never inflated or
  repaired.
- `BOOKMOBI` at offset 60 → `azw3`.
- Otherwise, if the probe decodes as UTF-8/UTF-16 without replacement characters → `txt` (never `md`,
  per D3).
- Every read is bounded by the buffer; every malformed-structure path returns `null` rather than
  throwing.

### D8 — Size and time bounds on an untrusted stream (round 1, H5)

An exported entry point must not let a hostile or broken provider fill the disk. **Who does what
matters** — round 2 (M2) caught v2 claiming a preflight "before opening" that sat in the coordinator,
i.e. after D6 had already opened the stream. Corrected split:

**In `ImportActivity`, before opening anything** (both are cursor queries — no stream needed):

- **Size preflight**: query `OpenableColumns.SIZE`; if present and `> MAX_IMPORT_BYTES` (**512 MiB**,
  chosen to clear the largest real fixtures with headroom), emit `IncomingItem.PreResolved(TooLarge)`
  and never open.
- **Free-space preflight**: when the size is known, require `booksDir.usableSpace > size + 32 MiB`,
  else `PreResolved(Failed)`.

**In the coordinator, after opening** (the backstop for absent or lying sizes):

- **Counting guard**: the copy runs through a counting stream that aborts with `TooLarge` past
  `MAX_IMPORT_BYTES` — this is what covers the unknown-size and infinite-stream cases.
- **Stall handling — queue liveness is the guarantee; unblocking the read is best-effort (round 2 H2;
  refined at round 3).** `withTimeout` alone does **not** work: coroutine cancellation is
  cooperative, and a blocking `InputStream.read` is not interruptible, so the copy loop would keep
  sitting in `read` while the coroutine is nominally "cancelled". Two mechanisms, with *different*
  strength claims — stated separately because conflating them is what round 3 flagged:
  - **Guaranteed — the queue never wedges.** Each item's copy runs as its own job on a dedicated
    thread (`newSingleThreadContext`-style, not a shared IO-dispatcher slot), and the worker awaits
    it under `withTimeoutOrNull(IMPORT_TIMEOUT)`. On expiry the worker records `Failed` and advances
    to the next item **unconditionally**, whether or not the copy thread ever unblocks. A pathological
    provider therefore costs at most one leaked thread, never a stalled queue.
  - **Best-effort — releasing the stuck thread.** A watchdog tracks bytes-read progress and, on
    `IMPORT_TIMEOUT` or `STALL_TIMEOUT` (60 s with zero progress), calls `stream.close()` from a
    different coroutine and interrupts the copy thread. For a provider-backed
    `ParcelFileDescriptor`/pipe stream this reliably makes the blocked `read` throw. It is **not**
    guaranteed for every stream shape (a regular-file fd or an `AssetFileDescriptor` slice can sit in
    an uninterruptible kernel read), which is exactly why the liveness guarantee above does not
    depend on it.
  - **No interaction with a *successful* import.** The watchdog only ever closes after the progress
    deadline has passed with the item still in flight; a completed copy cancels the watchdog before
    it can fire, so `close()` cannot race `BookImporter`'s own use of the stream on the success path.
  - WI-4 tests the liveness guarantee on the JVM (a `read()` that blocks forever ⇒ the worker still
    advances within `IMPORT_TIMEOUT`); WI-6 adds a **connected** stall case against a real
    slow/stalling provider, because that is the only place the best-effort claim can be observed.
- On every abort the partial temp file is removed by `BookImporter`'s existing `finally` (F7).

### D9 — Outcome delivery uses a buffered `Channel`, not a `SharedFlow` (round 1, H3)

A non-replaying `SharedFlow` drops emissions with no subscriber — precisely the cold-start case here,
where `MainActivity` is not collecting yet. The repo already solved this: the shipped `LibraryEvent`
bus is a `Channel(Channel.BUFFERED)` with a comment saying so (F11b). The coordinator uses the same
construct (`Channel(Channel.BUFFERED)` + `receiveAsFlow()`), so an outcome raised before
`MainActivity` collects is buffered and delivered when collection starts.

**Scope of the guarantee, stated honestly (round 2, M3).** This eliminates the *no-collector* loss.
It does **not** make delivery exactly-once across a collector handover: `receiveAsFlow` is
single-consumer and removes the element on receive, so an outcome received microseconds before a
rotation tears the collecting scope down can still be lost. That residual is accepted as a **Low**
(§13.9), for three reasons: the lost artifact is an advisory *failure toast*, never library state
(the row is already correct either way); the same race exists today on the shipped SAF path, so this
is not a regression; and the surface that would replace the toast is #2030's, where durable
delivery can be designed properly. No stronger claim is made anywhere in this plan.

---

## 4. Intent-filter design

### The rules that make this counter-intuitive

Each becomes an executable assertion in WI-2 rather than being trusted.

1. **`<data>` elements merge into a cross-product** within one `<intent-filter>` — schemes × hosts ×
   paths × mimeTypes. So MIME-based and path-based matching must live in **separate filters**.
2. **A filter with no `mimeType` does not match an intent that has one, and vice versa.** This is why
   the extension fallback is genuinely narrow: senders almost always set *some* type.
3. **`pathPattern` needs both a `scheme` and a `host`** — with no scheme all URI attributes are
   ignored; with no host, port and *all* path attributes are ignored.

Hazards that must be **tested**, not assumed:

- **`PATTERN_SIMPLE_GLOB` is not a regex** (`*` = zero-or-more of the *preceding* character; no
  reliable backtracking), hence the folklore that `.*\\.epub` fails on paths containing an earlier dot
  and the repeated-`.*\\.` workaround. WI-2 determines empirically whether the workaround is real
  here, and the table is corrected to the observed behaviour.
- **`pathPattern` is case-sensitive**; lowercase and all-uppercase variants are enumerated.
- **`pathSuffix` / `pathAdvancedPattern` are API 31+** and `minSdk = 26` (F14); an attribute the older
  platform does not understand is *ignored*, which would silently **widen** the filter to any content
  URI. Not used.
- **`content://` paths usually carry no filename**, so the path filter is a long-shot, not the
  mechanism.
- **`file://` has an empty authority** (round 1, M1): `host="*"` cannot match it, so a `file` +
  `host="*"` + `pathPattern` filter is dead weight. Compounding this, a sender targeting API 24+ cannot
  legally hand out a `file://` URI at all (`FileUriExposedException`). Filter B is therefore
  **`content`-only**; `file` is retained solely in the MIME filter A for legacy senders, where no host
  or path matching is involved.
- **An intent typed `*/*` matches ANY filter declaring any MIME type** — AOSP's
  `IntentFilter.findMimeType` special-cases a *wildcard intent type* against a filter whose type list
  is non-empty. **Corrected 2026-08-05 from WI-2's connected run against the real device
  `PackageManager`** (`ImportFilterResolutionConnectedTest`), which contradicted this section's
  earlier implication that no wildcard matching occurs. This is the **sender** being a wildcard, not
  our filter being broad: no `*/*` appears anywhere in the manifest, and the proof is that a concrete
  undeclared type still misses (`send_withAnImageDoesNotResolve`). It is unavoidable without removing
  every typed filter. Consequence for anyone writing or reading these tests: **filter narrowness is
  proven by a concrete undeclared type such as `image/jpeg`, never by `*/*`.** WI-5's runtime guard
  ("no `EXTRA_STREAM` and no `ClipData` URI ⇒ finish without importing") covers the payload-less case
  a wildcard sender can produce.

### Filter set (on `ImportActivity`; each a separate `<intent-filter>`)

| Filter | Action(s) | Categories | `<data>` |
|---|---|---|---|
| **A — VIEW by MIME** | `VIEW` | `DEFAULT`, `BROWSABLE` | schemes `content`, `file`; every MIME in D4's table **plus** `application/octet-stream` |
| **B — VIEW by extension (typeless only)** | `VIEW` | `DEFAULT`, `BROWSABLE` | scheme `content` **only**; `host="*"`; **no** mimeType; `pathPattern` × {`epub`,`pdf`,`txt`,`md`,`markdown`,`azw3`,`azw`,`mobi`,`prc`} × {lower, UPPER} × {0,1,2 leading `.*\\.` repeats} |
| **C — SEND** | `SEND` | `DEFAULT` | the same MIME list as A, incl. `text/plain` and `application/octet-stream` (D4); no scheme/host/path — `SEND` matches on type alone, since the payload is `EXTRA_STREAM`/`ClipData`, not `intent.data` |
| **D — SEND_MULTIPLE** | `SEND_MULTIPLE` | `DEFAULT` | same as C |

`BROWSABLE` on A/B lets a browser download open into VReader; it is deliberately absent from C/D.

**WI-2 proves this table — on a device, not on the JVM.** `ImportFilterResolutionConnectedTest`
(instrumented) drives the **real** `PackageManager.queryIntentActivities` against the merged
manifest, including negative space (`SEND`+`image/jpeg` must **not** resolve) and every empirical
`pathPattern` case; the JVM `ImportIntentFilterTest` is a fast **structural** check only, because
Robolectric's resolver is a shadow implementation whose `PatternMatcher` need not match the
platform's. The manifest is not shipped on the strength of this table, and §4 is corrected to
whatever the *connected* test observes.

---

## 5. Surface area

### New files

**`.../imports/IncomingBookResolver.kt`** (~140 lines)

```kotlin
/** Metadata-only result of the pre-open cursor query (D8's preflight input). */
data class IncomingMetadata(val displayName: String?, val declaredSize: Long?)

class IncomingBookResolver(
    private val resolver: ContentResolver,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    /** Metadata only (DISPLAY_NAME + SIZE) — no stream. Used for the pre-open preflight (D8). */
    suspend fun peek(uri: Uri): IncomingMetadata
    /**
     * D3's chain over EXACTLY ONE stream: opens once, sniffs via mark/reset, returns that same
     * rewound stream (round 2, M1 — a second open is a TOCTOU window and a one-shot provider may
     * refuse it or yield different bytes). The CALLER owns and must close the stream.
     * Throws ImportException.UnsupportedFormat when every step fails, closing the stream first.
     * Returns null only when the provider refuses to open at all.
     */
    suspend fun resolveAndOpen(uri: Uri): PendingImport?
    companion object {
        fun formatForMimeType(mime: String?): BookFormat?
        /** Strips control + Unicode-bidi chars, NFC-normalizes, collapses whitespace,
         *  caps at MAX_NAME_CHARS. Preserves CJK/RTL letters (D-M4). */
        fun sanitizeDisplayName(raw: String?): String
        const val MAX_NAME_CHARS = 200
        const val MAX_SOURCE_URI_CHARS = 2048
    }
}
```

**`.../imports/BookMagicSniffer.kt`** (~110 lines) — D7; no ZIP library, never inflates.

```kotlin
object BookMagicSniffer {
    /** Reads at most PROBE_BYTES from a mark-supporting stream and rewinds it.
     *  Returns null (never throws) for malformed input. NEVER returns md (D3). */
    fun sniff(input: InputStream): BookFormat?
    const val PROBE_BYTES = 4096
}
```

**`.../imports/IncomingImportCoordinator.kt`** (~190 lines) — D6, D8, D9.

```kotlin
sealed interface IncomingImportOutcome {
    data class Imported(val key: String, val format: BookFormat, val wasAlreadyPresent: Boolean) : IncomingImportOutcome
    data class Unsupported(val displayName: String) : IncomingImportOutcome
    data object Unreadable : IncomingImportOutcome
    data object TooLarge : IncomingImportOutcome
    data object Failed : IncomingImportOutcome
}

class IncomingImportCoordinator(
    private val importer: BookImporter,
    private val repository: LibraryRepository,
    private val booksDir: File,
    private val appScope: CoroutineScope,   // AppContainer's SupervisorJob scope
) {
    /**
     * Takes ownership of every PendingImport.stream and closes it on every path.
     * Items are appended to ONE process-wide queue drained by ONE worker coroutine, so imports are
     * sequential ACROSS concurrent ImportActivity instances, not merely within a call (round 2, H4).
     * PreResolved items are relayed to [outcomes] in order, one outcome per input URI.
     */
    fun enqueue(items: List<IncomingItem>)
    val outcomes: Flow<IncomingImportOutcome>      // buffered Channel.receiveAsFlow() (D9)
    /** Called ONCE at container construction, before any import can start (D-M5). */
    fun sweepStaleTempFiles(olderThanMillis: Long = 60 * 60 * 1000)
    companion object {
        const val MAX_IMPORT_BYTES = 512L * 1024 * 1024
        val IMPORT_TIMEOUT = 5.minutes
        val STALL_TIMEOUT = 60.seconds
        /** PROCESS-WIDE in-flight cap (queued + running), not per-enqueue (round 2, H4). */
        const val MAX_IN_FLIGHT = 20
    }
    /**
     * Round 3 (H1): the cap must be acquired BEFORE a stream is opened, or N concurrent
     * ImportActivity instances can each open MAX_BATCH fds before the coordinator ever sees them.
     * ImportActivity acquires one permit per URI immediately before resolveAndOpen and never opens
     * without one; the coordinator releases the permit when that item terminates (any outcome).
     * Backed by a Semaphore(MAX_IN_FLIGHT). A refused permit becomes PreResolved(Failed) with
     * nothing opened.
     */
    fun tryAcquireSlot(): Boolean
    fun releaseSlot()
}
```

`wasAlreadyPresent` is `repository.findBook(key) != null` evaluated **before** the upsert
(`LibraryRepository.kt:85`) — the honest duplicate signal a future #2030 design will consume.

**`.../imports/ImportActivity.kt`** (~150 lines)

```kotlin
class ImportActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?)  // resolve+open (alive) -> enqueue -> route -> finish
    internal companion object {
        /** VIEW -> intent.data; SEND/SEND_MULTIPLE -> EXTRA_STREAM, falling back to
         *  ClipData items (D-M9). Capped at MAX_BATCH; never throws. */
        fun urisFrom(intent: Intent): List<Uri>
        /** Per-INTENT cap. Distinct from the coordinator's PROCESS-WIDE MAX_IN_FLIGHT,
         *  which is what actually bounds concurrent ImportActivity instances. */
        const val MAX_BATCH = 20
    }
}
```

### Modified files

| File | Change |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | Register `ImportActivity` + the four filters (§4) + its translucent theme, `taskAffinity=""`, `noHistory`, `excludeFromRecents`. `MainActivity` untouched. |
| `.../data/BookImporter.kt` | Add **one** trailing optional parameter `format: BookFormat? = null`; non-null replaces the `formatForFilename` lookup at `:64-65`; null (every existing call site) is byte-identical. |
| `.../VReaderApp.kt` | Lazy `incomingBookResolver` + `incomingImportCoordinator` on `AppContainer`, sharing the existing `repository`/`importer` (`:67,70`); `sweepStaleTempFiles()` invoked once at construction. |
| `.../MainActivity.kt` | Collect `container.incomingImportCoordinator.outcomes` in the existing `LaunchedEffect` (`:66-74`); surface **failures only** through the existing `Toast` (D5). |
| `android/app/src/main/res/values/strings.xml` | Failure strings (create if absent). |
| `android/app/src/main/res/values/themes.xml` | The translucent `Theme.VReader.Import` (create if absent). |
| `docs/architecture.md` | The inbound-import path + the new **exported** component — landed in **WI-2**, the PR that first ships them (round 1, M7). |

**Version bump.** Per rule 40 "Batch mode — version-at-slot", the **orchestrator** allocates the
version at each merge slot; lanes never touch `android/version.properties`. Each WI carries a
`bump_tier` instead, which is why `version.properties` is absent from every `writes:` set and the
WI-1 ‖ WI-2 disjointness claim holds (round 1, H8).

### Files explicitly OUT of scope

- `docs/features.md`, `docs/parity/*` — orchestrator-owned; not touched by this plan or its WIs.
- Every reader activity and `foliate/FoliateBridge.kt` — D1 launches no reader.
- `LibraryScreen.kt` and every Compose surface — no new visible element (§7).
- `LibraryViewModel.kt` — the SAF path is untouched; the inbound path deliberately does not route
  through an Activity-scoped ViewModel.
- `BookOpener.kt` — real EPUB-metadata titles are a named follow-up (§9 R6).
- `BookFileProvider` / `BookShareIntent` — outbound share (#134).
- Any iOS path (rule 48 cross-platform write isolation).
- Persistable URI permissions — VReader copies at import and never revisits `sourceUri`.

---

## 6. Prior art, precedent, rejected alternatives

**Project precedent followed**: #134's `BookFileProvider` (`AndroidManifest.xml:47-58`) as the model
for a scoped, least-privilege exported surface; the SAF import path (`MainActivity.kt:62-64,108-112` →
`LibraryViewModel.kt:168-191`) for display-name resolution and typed failures, reusing the same
`formatForFilename` mapper so identities match; the shipped **buffered-`Channel`** event bus
(`LibraryViewModel.kt:161-165`) as the outcome-delivery pattern (D9); `RestoreImporter` as proof the
`importStream` seam already serves more than one caller; #106's converter-independent identity
decision (`BookImporter.kt:1-6`) as the reason sniffing may not override an extension (D3).

**External prior art**: iOS #59 in this repo (read in full for D1); Android's documented
`<intent-filter>` matching semantics (§4, verified by test); the common Android-reader pattern of a
broad MIME list plus `application/octet-stream`.

**Rejected alternatives**

| Rejected | Why |
|---|---|
| Intent-filters on `MainActivity` | Default `standard` launchMode (F15) → duplicate `MainActivity` over a reader (D2). |
| `android:mimeType="*/*"` | VReader in every share sheet for every file type. |
| **Excluding `text/plain`/`octet-stream` from `SEND`** (v1's D4) | Breaks the common `.txt`/`.md`/octet-stream file shares. Replaced by a runtime `EXTRA_TEXT`-only guard (round 1, H4). |
| `Theme.NoDisplay` for `ImportActivity` | A no-display activity must finish before becoming visible, but it must stay alive to open the streams (round 1, M2). |
| `CLEAR_TOP|SINGLE_TOP` **without** `NEW_TASK` | The exported activity runs in the *sender's* task, so this targets the wrong task (round 1, H1). |
| `pathSuffix` / `pathAdvancedPattern` | API 31+; ignored on API 26–30, silently widening the filter (F14). |
| `file` scheme in the pathPattern filter | `file://` has an empty authority, so `host="*"` cannot match; and modern senders cannot emit `file://` at all (round 1, M1). |
| Passing **URIs** to the coordinator | The grant dies with `ImportActivity`; streams must be opened while it is alive (round 1, H2). |
| A non-replaying `SharedFlow` for outcomes | Drops events with no subscriber — the cold-start case (round 1, H3). |
| A ZIP library for EPUB sniffing | Parses attacker-controlled structure; D7 reads only the first local header from the probe buffer (round 1, M3). |
| Auto-open the reader after import | Diverges from iOS; forks single/multi behaviour (D1). |
| Sniffing that overrides the extension | Changes the canonical key → duplicate rows (D3/F4). |
| Import on `ImportActivity`'s own scope | The activity finishes by design; the copy would be cancelled. |
| `takePersistableUriPermission` | Share intents rarely set the persistable flag, and VReader never re-reads the source. |

---

## 7. Rule 51 — visible surfaces

Intent-filters, an invisible routing activity, a resolver, a sniffer, and a coordinator are plumbing
with no visible delta. The Library the user lands on (D1) is the committed `vreader-fidelity-v1`
surface rendered by existing code.

**Three states genuinely want a surface and none is designed**: *in progress* (a cloud `content://`
can stream for many seconds with no visible change); *already in your library* (the duplicate case
correctly creates no row, so the visible result is nothing — silent success is indistinguishable from
silent failure); *success anchoring / partial multi-file result*. The tracker's cited design does not
cover these (§2's correction).

**Action taken, unconditionally, in this session** (rule 51 "Filing is immediate and unconditional"):
filed **`needs-design` #2030** — *"Design needed: Android book-import feedback (in-progress / added /
already-in-library / unsupported) for feature #155"*, labels `enhancement` + `needs-design`, listing
eight required states with line-cited current chrome and the mis-citation. Verified open via
`gh issue list --label needs-design --state open`.

**What #155 ships**: failures reuse the *already-shipped* `ImportFailed` toast (F11) verbatim — same
mechanism, same visual, new strings. Success and duplicate are silent, matching iOS
(`FileURLImportRouter.swift:66-73`; `VReaderApp.swift:365-367` passes a no-op unknown-extension
reporter). No new visual element. This plan contains **no** "if/when" deferral: the issue exists and is
cited by number in §13 and WI-5.

**Two behaviours audited against rule 51 and judged not to need design** (round 1, item 8): the
translucent `ImportActivity` renders nothing, so there is no surface to design; and the `CLEAR_TOP`
jump to the Library is *navigation to an already-designed screen*, the same destination the LAUNCHER
icon reaches. Both are behaviour, not new chrome.

---

## 8. Gate-5 production reachability (rule 47:90)

The deliverable *is* a production entry point, so evidence must exceed "bytes were imported".

**Named user path**: *Files (or Downloads) → long-press a `.epub` → **Open with** → VReader → lands in
the Library with the book present.* A second pass covers *Files → Share → VReader*.

**Release-variant caveat, established by inspection.** `android/app/build.gradle.kts` has **no
`buildTypes` block and no `signingConfig`** (`grep -n 'buildTypes\|signingConfig'` → 0 hits), so
`assembleRelease` produces an **unsigned** APK that cannot be installed. Round 2 (H5) is right that
debug instrumentation alone does not discharge rule 47:90, but "install the release build" is not
available here. The evidence is therefore split so that each half is actually obtainable, and
together they cover the claim:

- **Release ships the filters** — proven *statically*, on release artifacts: the merged release
  manifest (`app/build/intermediates/merged_manifests/release/AndroidManifest.xml`, produced by
  `:app:processReleaseManifest`) and `aapt2 dump xmltree` over the assembled release APK both show
  `ImportActivity` with all four filters and `exported="true"`. This is sound because
  `app/src/debug/AndroidManifest.xml` contributes **no** intent-filter (F1), so the debug and release
  merged manifests are identical for this feature — a fact the evidence file asserts by diffing the
  two merged manifests' `<activity android:name=".imports.ImportActivity">` blocks.
- **A real user can traverse it** — proven *dynamically* on the installed debug build, whose merged
  manifest was just shown to be identical here.

**Required evidence:**

1. The two merged manifests diffed, plus `aapt2 dump xmltree` on the **release** APK — filters
   present, `exported="true"`, `ImportActivity` sourced from `app/src/main/` (nothing from
   `app/src/debug/`).
2. `adb shell cmd package query-activities -a android.intent.action.VIEW -t application/epub+zip -d content://…`
   lists `com.vreader.app/.imports.ImportActivity` — the filter is live in the **installed** APK, on a
   real `PackageManager` (this is also the device-side check that backstops WI-2's `pathPattern`
   matrix — round 2, M4).
3. A **real sender** drives it: DocumentsUI's own "Open with" chooser, with a screenshot showing
   VReader listed and the tap landing in the Library. `am start` is a harness convenience; the chooser
   screenshot is the shipped path.
4. Per-format round trip (§11's fixture policy, F20).
5. Duplicate pass: SAF-import a book, then "Open with" the same file; `count(*)` unchanged, key equal.
6. Cold start (after force-stop) and warm start (reader open) — D2's task behaviour observed, with
   exactly one `MainActivity` instance after.

All device steps run under **`scripts/run-android-verify.sh`** (round 1, H9 — no raw `adb` outside the
wrapper); `ANDROID_SERIAL=emulator-5554`; never drive the emulator during an in-flight instrumentation
run (rule 52 Cause D); the connected task wipes `/sdcard/Android/data/<pkg>/`, so re-push fixtures
every run.

**Gradle invocation (round 2, H1).** There is **no `gradlew` at the repo root** — only
`android/gradlew` (verified: `ls gradlew` → No such file). Every `ANDROID_CMD` in this plan is
therefore `cd android && ./gradlew …`; the wrapper does not `cd` for you
(`scripts/run-android-tests.sh:37-41` runs `$ANDROID_CMD` as given).

---

## 9. Risks + mitigations

| # | Risk | Sev | Mitigation |
|---|---|---|---|
| R1 | `pathPattern` behaves differently from §4, so filter B never fires. | Med | WI-2 asserts against the real `PackageManager`; the table is corrected to observed behaviour. Filters A/C/D carry the feature regardless. |
| R2 | Broad `octet-stream` / `text/plain` acceptance makes VReader offer itself for non-books. | Med | Runtime `EXTRA_TEXT`-only guard (D4); D3 rejects what it cannot identify with the existing toast; accepted cost recorded in §13. |
| R3 | The URI grant dies when `ImportActivity` finishes, mid-copy. | **High** | D6: streams are opened while the activity is alive and handed over already-open; the coordinator owns and closes them. WI-4/WI-5 assert a copy completes after the activity is destroyed. |
| R4 | Process death mid-import orphans a `.part` file. | Low | `BookImporter.kt:117-120` handles the in-process case; `sweepStaleTempFiles` runs **once at container construction, before any importer is reachable**, and is age-gated to >1 h so it cannot race a live import (round 1, M5). |
| R5 | Sniffing consumes bytes, corrupting the hash. | **High** | `BookMagicSniffer` requires `markSupported()` (wrapping when absent) and always rewinds; WI-3 asserts the resulting key equals the SAF-imported key for identical bytes. |
| R6 | Missing display name ⇒ a useless title. | Low | DISPLAY_NAME → `lastPathSegment` → decoded segment → `"Untitled"` + the resolved extension. Real EPUB metadata via `BookOpener.readMetadata` is a named follow-up. |
| R7 | Hostile inbound AZW3/EPUB reaches the foliate WebView. | Med | Existing hardening: `allowFileAccess=false`, `allowUniversalAccessFromFileURLs=false`, section scripts disabled (F17); D7 never inflates archive content at import. (D1 is *not* counted here — see D1's honest-scope note.) |
| R8 | Path traversal / injection via a hostile `displayName`. | Med | Structurally prevented for the artifact path (F6). **Additionally** (round 1, M4) `sanitizeDisplayName` strips control and Unicode-bidi characters, NFC-normalizes, and caps length before the name becomes a title; `sourceUri` is capped at 2048 chars before persisting. |
| R9 | `SEND_MULTIPLE` DoS / fd exhaustion, incl. **concurrent `ImportActivity` instances** (two files shared in quick succession, or split-screen). | Med | ONE process-wide queue drained by ONE worker, so sequencing holds across instances; `MAX_BATCH = 20` per intent **and** `MAX_IN_FLIGHT = 20` process-wide bound the open fds; excess is closed and relayed as `Failed`; per-item failure isolation (round 2, H4). A concurrent same-key import is safe independently: `File.createTempFile` gives each a unique temp and the promote is an `ATOMIC_MOVE` into a key-derived name (F6, F7). |
| R10 | Hostile/broken provider returns a huge or infinite stream and fills storage, **or stalls forever**. | **High** | D8: `SIZE` + free-space preflight *before opening*; a counting guard past `MAX_IMPORT_BYTES` for unknown/lying sizes; and a watchdog that **closes the fd** on a 5-min total or 60-s no-progress stall — because coroutine cancellation cannot interrupt a blocking `read` (round 1 H5; round 2 H2). |
| R11 | Storage full during the copy. | Med | Free-space preflight (D8) plus the existing `IOException` → temp-deleted-in-`finally` path (F7) → `Failed` → existing toast. |
| R12 | An extension that lies about the format. | Low | Accepted (identity stability); reader-side open failure is the backstop. |
| R13 | An intent-redirection / confused-deputy attack: a hostile `EXTRA_STREAM` naming VReader's **own** `BookFileProvider` authority, tricking VReader into copying its own private file. | Med | `ImportActivity` rejects any URI whose authority equals `${applicationId}.fileprovider` before opening; asserted by a WI-5 test. Impact is bounded anyway (the result would be a duplicate of a book the user already owns, in app-private storage), but the guard is cheap. |
| R14 | Android 14+ restrictions on background activity starts. | Low | Every start here is user-initiated and foreground (a chooser tap), the sanctioned case; the cold/warm-start passes in §8 verify it on the target API. |

---

## 10. Work-item sequencing

Six WIs. **Foundational** = no user-observable behaviour; **behavioral** = slice-verified on the
emulator (rule 47 Gate 5). Per rule 40 batch mode, no WI writes `android/version.properties`.

### WI-1 — `BookImporter` format override (foundational, ~40 LOC)

```yaml
id: feat:#155/WI-1
tier: foundational
depends: []
platform: android-app
bump_tier: patch
writes:
  - android/app/src/main/kotlin/com/vreader/app/data/BookImporter.kt
  - android/app/src/test/kotlin/com/vreader/app/data/BookImporterTest.kt
spec: |
  Add ONE trailing optional parameter to importStream:
      suspend fun importStream(sourceUri: String, displayName: String, input: InputStream,
                               expectedKey: String? = null, format: BookFormat? = null): Book
  When format != null it REPLACES the DocumentFingerprint.formatForFilename(displayName) lookup at
  BookImporter.kt:64-65; when null, behaviour is byte-identical to today (including throwing
  ImportException.UnsupportedFormat for an unknown extension). Everything else in the method is
  unchanged. Identity is Identity.canonicalKey(format.name, sha256, byteCount) — Identity.kt:22-23.
  Existing call sites that must still compile unchanged — the COMPLETE production set, verified by
  `grep -rn importStream android/app/src/main/kotlin/`:
    library/LibraryViewModel.kt:182, backup/RestoreImporter.kt:168, opds/OpdsAcquisitionService.kt:38
  (r3 L3: v3 omitted the OPDS caller). Re-run the grep before editing in case a caller was added.
tests:
  - "format=null reproduces today's behaviour exactly, incl. UnsupportedFormat for '.xyz'"
  - "format=BookFormat.epub with displayName 'x.bin' imports as epub, key 'epub:<sha>:<n>'"
  - "explicit format=X and extension-derived format X on the same bytes produce the SAME canonicalKey"
  - "every pre-existing BookImporterTest case still passes unmodified"
acceptance:
  - "The parameter is LAST and defaulted; no existing call site is edited."
  - "All four tests above are RED before the change and GREEN after."
gate: |
  ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests '*BookImporterTest*'" scripts/run-android-tests.sh
```

### WI-2 — Manifest filters, `ImportActivity` skeleton, docs sync (behavioral, ~170 LOC)

```yaml
id: feat:#155/WI-2
tier: behavioral
depends: []
platform: android-app
bump_tier: minor
writes:
  - android/app/src/main/AndroidManifest.xml
  - android/app/src/main/kotlin/com/vreader/app/imports/ImportActivity.kt
  - android/app/src/main/res/values/strings.xml
  - android/app/src/main/res/values/themes.xml
  - android/app/src/test/kotlin/com/vreader/app/imports/ImportIntentFilterTest.kt
  - android/app/src/test/kotlin/com/vreader/app/imports/ImportActivityUriExtractionTest.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/imports/ImportFilterResolutionConnectedTest.kt
  - docs/architecture.md
spec: |
  Declare ImportActivity with android:exported="true", android:taskAffinity="",
  android:noHistory="true", android:excludeFromRecents="true", and a TRANSLUCENT (NOT NoDisplay)
  theme Theme.VReader.Import: windowIsTranslucent=true, windowBackground=@android:color/transparent,
  windowNoTitle=true, windowIsFloating=false, backgroundDimEnabled=false.
  FOUR SEPARATE <intent-filter> elements (data elements MERGE into a cross-product within one filter,
  so MIME and pathPattern matching MUST NOT share a filter):
    A  VIEW  + DEFAULT + BROWSABLE — <data scheme="content"/>, <data scheme="file"/>, and one
       <data mimeType=.../> per: application/epub+zip, application/x-epub+zip, application/epub,
       application/pdf, application/x-pdf, text/plain, text/markdown, text/x-markdown,
       application/vnd.amazon.ebook, application/vnd.amazon.mobi8-ebook,
       application/x-mobipocket-ebook, application/octet-stream
    B  VIEW  + DEFAULT + BROWSABLE — scheme="content" ONLY (file:// has an empty authority so
       host="*" cannot match it), host="*", NO mimeType, pathPattern for each of
       {epub,pdf,txt,md,markdown,azw3,azw,mobi,prc} in lowercase AND uppercase, each with 0/1/2
       leading ".*\\." repeats (PATTERN_SIMPLE_GLOB has no reliable backtracking).
    C  SEND + DEFAULT — the same mimeType list as A. No scheme/host/path (SEND matches on type only;
       the payload is EXTRA_STREAM/ClipData, not intent.data). No BROWSABLE.
    D  SEND_MULTIPLE + DEFAULT — same list as C.
  MainActivity's own intent-filter block must remain byte-identical.
  ImportActivity in this WI is a SKELETON: it implements only the companion urisFrom(intent) and
  finish(); the import wiring is WI-5.
    urisFrom: VIEW -> listOfNotNull(intent.data); SEND -> EXTRA_STREAM (Parcelable) else ClipData
    items; SEND_MULTIPLE -> EXTRA_STREAM ArrayList else ClipData items; capped at MAX_BATCH=20;
    returns emptyList for a missing/malformed extra; NEVER throws.
  docs/architecture.md: document the inbound-import path and the NEW EXPORTED component in THIS PR
  (rule 24 — a new component + user-visible capability syncs in the PR that lands it).
  TEST PLACEMENT (round 2, M4): Robolectric's intent resolution is a SHADOW PackageManager, not the
  real one, and its PatternMatcher may not reproduce device pathPattern behaviour. So:
    - ImportIntentFilterTest (JVM/Robolectric) = a fast STRUCTURAL check: four filters exist, with the
      expected actions/categories/mimeTypes/schemes, and MainActivity is unchanged. It does NOT
      establish real matching.
    - ImportFilterResolutionConnectedTest (androidTest, REAL PackageManager on device) = the
      AUTHORITATIVE matching matrix, incl. every pathPattern case. §4's table is corrected to what
      THIS test observes, not to what the JVM test observes.
tests:
  - "JVM structural: four separate filters with the expected actions/categories/mimeTypes/schemes; MainActivity's filter block byte-identical"
  - "CONNECTED, real PackageManager.queryIntentActivities resolves ImportActivity for: VIEW+application/epub+zip, VIEW+application/pdf, VIEW+application/octet-stream, SEND+application/epub+zip, SEND+text/plain, SEND_MULTIPLE+application/pdf"
  - "CONNECTED NEGATIVE: SEND+image/jpeg does NOT resolve to ImportActivity"
  - "CONNECTED: pathPattern asserted empirically for a content URI whose path contains an earlier dot, and for an uppercase .EPUB"
  - "urisFrom: VIEW/SEND/SEND_MULTIPLE, ClipData-only payload, missing extra, wrong extra type, >20 URIs, empty"
acceptance:
  - "Four separate filters exactly as specified; MainActivity untouched."
  - "The CONNECTED resolution matrix (incl. the negative case) passes on a real device PackageManager; §4's table matches the observed behaviour."
  - "docs/architecture.md updated in this PR."
gate: |
  ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests '*ImportIntentFilterTest*' --tests '*ImportActivityUriExtractionTest*'" scripts/run-android-tests.sh
  ANDROID_CMD="cd android && ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.imports.ImportFilterResolutionConnectedTest" ANDROID_SERIAL=emulator-5554 scripts/run-android-tests.sh
```

### WI-3 — `IncomingBookResolver` + `BookMagicSniffer` (foundational, ~250 LOC)

```yaml
id: feat:#155/WI-3
tier: foundational
depends: [feat:#155/WI-1]
platform: android-app
bump_tier: patch
writes:
  - android/app/src/main/kotlin/com/vreader/app/imports/IncomingBookResolver.kt
  - android/app/src/main/kotlin/com/vreader/app/imports/BookMagicSniffer.kt
  - android/app/src/test/kotlin/com/vreader/app/imports/IncomingBookResolverTest.kt
  - android/app/src/test/kotlin/com/vreader/app/imports/BookMagicSnifferTest.kt
spec: |
  RESOLUTION CHAIN, in this exact order, first success wins:
    1. ContentResolver DISPLAY_NAME (OpenableColumns.DISPLAY_NAME) -> DocumentFingerprint
       .formatForFilename  (epub|pdf|txt|md/markdown|azw3/azw/mobi/prc -> BookFormat)
    2. uri.lastPathSegment extension -> the same mapper
    3. ContentResolver.getType(uri) -> MIME MAP:
         application/epub+zip, application/x-epub+zip, application/epub      -> epub
         application/pdf, application/x-pdf                                   -> pdf
         text/plain                                                           -> txt
         text/markdown, text/x-markdown                                       -> md
         application/vnd.amazon.ebook, application/vnd.amazon.mobi8-ebook,
           application/x-mobipocket-ebook                                     -> azw3
         application/octet-stream, */*, null                                  -> NOTHING (fall through)
    4. BookMagicSniffer.sniff
    5. else throw ImportException.UnsupportedFormat(displayName)
  INVARIANT (identity stability): steps 1-2 ALWAYS beat 3-4. Format is part of the canonical key
  ("format:sha:bytes", Identity.kt:22-23), so a sniff that contradicts an extension would create a
  DUPLICATE row for an already-imported book. Sniffing only fills a gap.
  TWO ENTRY POINTS, and only ONE of them opens a stream:
    peek(uri): IncomingMetadata  — a cursor query ONLY (DISPLAY_NAME + SIZE). No stream. This is what
      the caller uses for the pre-open size/free-space preflight (D8).
    resolveAndOpen(uri): PendingImport?  — opens EXACTLY ONE stream, runs steps 1-4 against it
      (sniffing via mark/reset), and returns that SAME rewound stream inside PendingImport. Do NOT
      add a separate openStream(): sniffing one stream and importing another is a TOCTOU window, and
      a one-shot provider may refuse the second open or return different bytes. On
      UnsupportedFormat the stream is CLOSED before the exception propagates. Returns null only when
      the provider refuses to open at all.
  declaredSize comes from OpenableColumns.SIZE (null when absent or negative).
  The returned stream must have markSupported()==true (wrap in BufferedInputStream when not); the
  CALLER owns and closes it.
  sanitizeDisplayName: NFC-normalize, strip Unicode control chars (incl. NUL, CR, LF) and the FULL
  Bidi_Control set — U+061C, U+200E, U+200F, U+202A-U+202E, U+2066-U+2069 (the first three were
  missing in v2; a stray U+200F still reverses rendered order) — collapse whitespace runs, trim, cap
  at 200 chars PRESERVING the extension, fall back to "Untitled" + the resolved extension when empty.
  CJK and RTL LETTERS must be preserved — only control/bidi-control chars are removed.
  SNIFFER (bounded, NO zip library, NEVER inflates — the input is attacker-controlled):
    reads <=4096 bytes from a mark-supporting stream and ALWAYS rewinds; returns null, never throws.
    "%PDF-" @0                       -> pdf
    "PK\x03\x04" @0                  -> read, FROM THE BUFFER ONLY: compression method @8,
                                        compressed size @18, uncompressed size @22, filename len @26,
                                        extra len @28. Accept epub ONLY IF ALL hold: first entry named
                                        exactly "mimetype"; STORED (method 0); extra len == 0;
                                        compressed size == uncompressed size == 20; and the 20 content
                                        bytes == "application/epub+zip". (The size/extra checks are the
                                        OCF requirements and stop a crafted header steering the read.)
                                        Otherwise null.
    "BOOKMOBI" @60                   -> azw3
    probe decodes as UTF-8/UTF-16 with no replacement chars -> txt
    NEVER returns md (no reliable magic; md is text) — see the §12 compatibility caveat.
tests:
  - "chain order 1..5 incl. each fall-through"
  - "a DISPLAY_NAME extension ALWAYS wins over a contradicting sniff result"
  - "octet-stream / */* / null getType contribute nothing"
  - "stream preservation: post-sniff SHA-256 == SHA-256 of the untouched bytes"
  - "non-mark-supporting stream is wrapped, not rejected"
  - "sniffer: %PDF-, stored-mimetype epub zip, BOOKMOBI@60, UTF-8, UTF-16, random binary -> null"
  - "sniffer: DEFLATED first entry -> null; first entry not named 'mimetype' -> null; NON-ZERO extra length -> null; declared size != 20 -> null; truncated local header -> null; zip-bomb-shaped input is never inflated"
  - "sniffer: zero-byte, and input shorter than the probe window"
  - "resolveAndOpen opens exactly ONE stream (a counting ContentResolver asserts openInputStream called once) and returns it rewound"
  - "resolveAndOpen CLOSES the stream when it throws UnsupportedFormat"
  - "sanitizeDisplayName: newline, NUL, 10k chars, CJK preserved, RTL letters preserved, EACH of U+061C/U+200E/U+200F/U+202E stripped, empty -> Untitled+ext"
  - "displayName '../../etc/passwd.epub' yields a title with no traversal and (via WI-1) an artifact under booksDir"
acceptance:
  - "Every test above GREEN; the identity-stability invariant has an explicit named test."
gate: |
  ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests '*IncomingBookResolverTest*' --tests '*BookMagicSnifferTest*'" scripts/run-android-tests.sh
```

### WI-4 — `IncomingImportCoordinator` + container wiring (foundational, ~240 LOC)

```yaml
id: feat:#155/WI-4
tier: foundational
depends: [feat:#155/WI-1, feat:#155/WI-3]
platform: android-app
bump_tier: patch
writes:
  - android/app/src/main/kotlin/com/vreader/app/imports/IncomingImportCoordinator.kt
  - android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt
  - android/app/src/test/kotlin/com/vreader/app/imports/IncomingImportCoordinatorTest.kt
spec: |
  enqueue(items: List<IncomingItem>) where
    IncomingItem = Ready(PendingImport) | PreResolved(IncomingImportOutcome)
    PendingImport(uri, displayName, format, sourceUri: String /* ALREADY capped to
      MAX_SOURCE_URI_CHARS=2048 by WI-5 */, declaredSize: Long?, stream: InputStream /* ALREADY OPEN,
      REWOUND */)
  The coordinator MUST call importStream(sourceUri = pending.sourceUri, displayName =
  pending.displayName, input = <counting-guarded stream>, format = pending.format) — pass the
  PRE-CAPPED sourceUri through verbatim; never re-derive it from pending.uri.toString(), which would
  silently discard the cap (r4 M1).
  WHY THE ENVELOPE: resolution/open failures happen in ImportActivity (it owns the URI grant), so if
  enqueue accepted only successes, Unsupported/Unreadable/TooLarge would have NO route to `outcomes`
  and would never toast. PreResolved items are relayed to the channel IN ORDER, giving exactly one
  outcome per input URI regardless of where the failure occurred.
  STREAM OWNERSHIP: the coordinator takes ownership and CLOSES every stream on EVERY path —
  success, unsupported, too-large, timeout, exception, and items rejected by MAX_IN_FLIGHT.
  SCOPES (be precise): enqueue is CALLED from ImportActivity.lifecycleScope, but the copy runs on the
  injected appScope (AppContainer's SupervisorJob + Dispatchers.IO). Cancelling the CALLER's
  lifecycleScope MUST NOT cancel an in-flight copy. Cancelling appScope itself SHOULD cancel it.
  Test this with two distinct TestScopes — do not conflate them.
  PROCESS-WIDE SEQUENCING: enqueue appends to ONE queue drained by ONE long-lived worker coroutine
  owned by the (singleton) coordinator. Sequencing and the in-flight cap must hold ACROSS CONCURRENT
  ImportActivity INSTANCES (two files shared back-to-back, or split-screen) — a per-call loop would
  not. MAX_IN_FLIGHT = 20 counts queued + running process-wide; items beyond it are closed
  immediately and relayed as Failed. (A concurrent same-key import is independently safe:
  File.createTempFile gives a unique temp and the promote is an ATOMIC_MOVE — BookImporter.kt:70,130-141.)
  SIZE BOUNDS (the stream is untrusted): the DECLARED-size and free-space rejections happen in
  ImportActivity BEFORE opening (they are cursor queries — see WI-5); the coordinator's job is the
  post-open backstop: ALWAYS wrap the stream in a counting guard that aborts with TooLarge past
  MAX_IMPORT_BYTES even when declaredSize was null or lied.
  TIMEOUT — TWO MECHANISMS WITH DIFFERENT STRENGTHS. Do not conflate them (this is D8; r4 H2 caught
  this block still asserting the old, weaker framing):
    GUARANTEED (this is what liveness rests on): run each item's copy as its own job on a DEDICATED
      THREAD, and have the worker await it under withTimeoutOrNull(IMPORT_TIMEOUT = 5 min). On expiry
      the worker records Failed, releases the item's permit, and advances to the next item
      UNCONDITIONALLY — whether or not the copy thread ever unblocks. A pathological provider costs at
      most one leaked thread + fd; it can NEVER wedge the queue. Note the cap interaction: because the
      permit is released when the WORKER gives up (not when the thread finally dies), leaked threads
      cannot accumulate into a permanently-wedged admission gate.
    BEST-EFFORT (an optimization, never a correctness dependency): a watchdog tracks bytes-read
      progress and, on IMPORT_TIMEOUT or STALL_TIMEOUT (60 s with zero progress), calls
      stream.close() from a DIFFERENT coroutine and interrupts the copy thread. For a provider-backed
      ParcelFileDescriptor/pipe this usually makes the blocked read throw IOException promptly. It is
      NOT guaranteed for every stream shape (a regular-file fd or an AssetFileDescriptor slice can sit
      in an uninterruptible kernel read) — which is exactly why liveness does not depend on it.
    NO RACE WITH SUCCESS: the watchdog is cancelled the moment the copy completes, so close() cannot
      race BookImporter's own use of the stream on the success path.
  Write the tests to assert the GUARANTEE (worker advances, permit returns) and to treat the
  best-effort release as observational only — a JVM test must NOT be written so that it passes only
  if close() unblocks the read.
  OUTCOMES via a BUFFERED Channel + receiveAsFlow() — NOT a SharedFlow. A non-replaying SharedFlow
  drops emissions when MainActivity is not yet collecting (cold start / rotation); the shipped
  LibraryEvent bus uses Channel(Channel.BUFFERED) for exactly this reason (LibraryViewModel.kt:161-165).
  wasAlreadyPresent = repository.findBook(key) != null evaluated BEFORE importStream's upsert
  (LibraryRepository.kt:85).
  Map: ImportException.UnsupportedFormat -> Unsupported; null/refused stream -> Unreadable;
  IOException/SecurityException mid-copy -> Failed; cap exceeded -> TooLarge; timeout -> Failed.
  sweepStaleTempFiles(olderThanMillis = 1h): deletes booksDir "import-*.part" files older than the
  threshold. Called EXACTLY ONCE from AppContainer construction, BEFORE the importer is obtainable,
  and age-gated so it can never race a live import.
  AppContainer: add lazy incomingBookResolver + incomingImportCoordinator reusing the EXISTING
  repository/importer singletons (VReaderApp.kt:67,70) and the existing app scope.
tests:
  - "sequential ordering; one outcome per item; outcomes are buffered and delivered to a LATE collector"
  - "PreResolved items are relayed in order: a mixed list of Ready+PreResolved yields one outcome per input, in input order"
  - "wasAlreadyPresent=true on a duplicate AND no second row is added"
  - "cancelling the CALLER scope does not cancel the copy; cancelling appScope does"
  - "per-item failure isolation: item 2 of 3 throws, items 1 and 3 still import, 3 outcomes emitted"
  - "PROCESS-WIDE sequencing: two enqueue() calls interleaved from different scopes still import strictly one-at-a-time (a recording importer asserts no overlap)"
  - "MAX_IN_FLIGHT via permits: tryAcquireSlot returns false once 20 are outstanding, and each terminal outcome releases exactly one permit (no leak across success/failure/timeout paths)"
  - "LIVENESS (assert the GUARANTEE, not the best-effort close): an InputStream whose read() blocks forever and IGNORES close() still lets the worker record Failed, release the permit, and advance to the NEXT item within IMPORT_TIMEOUT — the test must fail if liveness depended on close() unblocking the read"
  - "the coordinator passes pending.sourceUri VERBATIM to importStream (a spy importer asserts the capped value, not a re-derived uri.toString())"
  - "every stream is closed on every path (a recording InputStream asserts closed==true), incl. rejected-past-MAX_IN_FLIGHT and timeout"
  - "declaredSize null + stream longer than cap -> TooLarge; infinite stream -> TooLarge in bounded time"
  - "STALL: an InputStream whose read() blocks indefinitely is unblocked by the watchdog's close(); the item resolves to Failed within STALL_TIMEOUT and the worker proceeds to the NEXT item (proves cancellation alone would not have sufficed)"
  - "timeout -> Failed, stream closed, no .part left"
  - "mid-stream SecurityException (revoked grant) -> Failed, no .part left"
  - "sweepStaleTempFiles deletes an aged .part and LEAVES a fresh one"
acceptance:
  - "Every test above GREEN; stream-closure, process-wide sequencing, the stall-interrupt, and the two-scope cancellation semantics each have an explicit named test."
gate: |
  ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests '*IncomingImportCoordinatorTest*'" scripts/run-android-tests.sh
```

### WI-5 — End-to-end wiring (behavioral, ~150 LOC)

```yaml
id: feat:#155/WI-5
tier: behavioral
depends: [feat:#155/WI-2, feat:#155/WI-4]
platform: android-app
bump_tier: minor
writes:
  - android/app/src/main/kotlin/com/vreader/app/imports/ImportActivity.kt
  - android/app/src/main/kotlin/com/vreader/app/MainActivity.kt
  - android/app/src/main/res/values/strings.xml
  - android/app/src/androidTest/kotlin/com/vreader/app/imports/IncomingIntentImportConnectedTest.kt
spec: |
  ImportActivity.onCreate:
    1. uris = urisFrom(intent). If EMPTY and the action is SEND/SEND_MULTIPLE (the EXTRA_TEXT-only
       plain-text-snippet case), finish() IMMEDIATELY — no import, and do NOT launch MainActivity;
       the user returns to the sending app.
    2. lifecycleScope.launch { withContext(IO) { for each URI, IN THIS ORDER:
         a. CONFUSED-DEPUTY GUARD: if uri.authority == "${applicationId}.fileprovider" ->
            PreResolved(Unreadable). (r3 H3: this MUST emit an item, not `continue` — a silently
            dropped URI breaks the one-outcome-per-URI invariant.)
         b. PERMIT (r3 H1), with LEAK-PROOF OWNERSHIP (r4 H1 — v4 named the owner but not the
            exception/cancellation path, so 20 leaks could permanently wedge admission):
              if !coordinator.tryAcquireSlot() -> PreResolved(Failed), open NOTHING, next URI.
              Otherwise the permit is held under a try/finally spanning the REST of this URI's block:
                var transferred = false
                try { … steps c-f …; if (item is Ready) { enqueue-list += item; transferred = true } }
                finally { if (!transferred) coordinator.releaseSlot() }
              OWNERSHIP TRANSFERS TO THE COORDINATOR IF AND ONLY IF a Ready item actually reaches
              enqueue(). Every other exit — PreResolved, a thrown exception, or CancellationException
              from the activity being destroyed mid-loop — releases in the finally. The coordinator
              then releases exactly once per Ready item at its TERMINAL outcome (success, failure,
              too-large, or the worker giving up on a stalled item — see WI-4).
              INVARIANT: outstanding permits return to 0 after any batch, however it ends.
            The permit is acquired BEFORE any stream exists, so concurrent ImportActivity instances
            cannot collectively exceed MAX_IN_FLIGHT open fds.
         c. resolver.peek(uri) -> DISPLAY_NAME + SIZE (cursor query, NO stream yet), wrapped in
            try/catch: ANY exception (SecurityException, IllegalStateException, a provider that
            throws on query) -> PreResolved(Unreadable). (r3 H3.)
         d. PRE-OPEN preflight (D8): declaredSize > MAX_IMPORT_BYTES -> PreResolved(TooLarge);
            declaredSize known && booksDir.usableSpace <= declaredSize + 32 MiB -> PreResolved(Failed).
            These run BEFORE opening — that is the whole point of "reject before opening".
         e. sourceUri = uri.toString().take(MAX_SOURCE_URI_CHARS = 2048)  — computed HERE and carried
            on PendingImport.sourceUri, which is the exact value the coordinator later passes as
            importStream(sourceUri = …). (r3 M1: v3 stated the cap with no data path.)
         f. resolver.resolveAndOpen(uri) -> Ready(PendingImport). Exception mapping must be TOTAL
            (r4 H3 — an enumerated list let a hostile provider's RuntimeException escape the loop and
            produce ZERO outcomes for that URI):
              catch (e: CancellationException) { throw e }        // honor structured cancellation
              catch (e: ImportException.UnsupportedFormat) { PreResolved(Unsupported(name)) }
              catch (e: Throwable) { PreResolved(Unreadable) }    // CATCH-ALL, not an enum of types
            A null return likewise -> PreResolved(Unreadable). The catch-all is deliberate: the URI
            and the provider behind it are attacker-controlled, so the set of throwables is not
            knowable in advance.
       } } — the streams MUST be opened WHILE THIS ACTIVITY IS ALIVE. A
       FLAG_GRANT_READ_URI_PERMISSION grant dies when this activity finishes; an already-open fd
       survives it. Never pass bare URIs to the coordinator.
    3. TOTAL INVARIANT (r3 H3): every URI returned by urisFrom produces EXACTLY ONE IncomingItem —
       no branch may `continue`, `return`, or throw out of the loop. Assert it with a test that
       feeds one URI of every failure class at once and counts outcomes == inputs.
    4. coordinator.enqueue(items)   // List<IncomingItem>, one per input URI
    5. startActivity(Intent(this, MainActivity::class.java).addFlags(
           FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_CLEAR_TOP or FLAG_ACTIVITY_SINGLE_TOP))
       NEW_TASK is REQUIRED: an externally-started activity runs in the SENDER's task, so without it
       CLEAR_TOP would target the wrong task and create a second MainActivity.
    6. finish()
  The activity renders nothing (translucent theme from WI-2) but MUST NOT be Theme.NoDisplay,
  because steps 3-5 run before finish().
  MainActivity: collect container.incomingImportCoordinator.outcomes inside the EXISTING
  LaunchedEffect at MainActivity.kt:66-74 and show the EXISTING Toast for FAILURE outcomes only
  (Unsupported / Unreadable / TooLarge / Failed). Imported -> SILENT, both new and duplicate.
  RULE 51: add NO new visible surface. The in-progress / added / already-in-library / unsupported
  treatments are BLOCKED on needs-design #2030 and are out of scope for this WI.
tests:
  - "VIEW with a real EPUB content URI -> exactly one library row, Library on screen"
  - "the SAME file sent again -> still one row (dedup), still lands in the Library"
  - "unsupported .docx -> existing ImportFailed toast, no crash"
  - "SEND carrying only EXTRA_TEXT -> finishes silently, no import, MainActivity NOT launched"
  - "a URI whose authority is our own fileprovider -> rejected, no import"
  - "warm start with a reader open: exactly ONE MainActivity instance afterwards"
  - "cold start after force-stop -> imports and lands in the Library"
  - "the import completes even though ImportActivity is already destroyed (grant-revocation path)"
  - "an UNSUPPORTED file still produces exactly one toast — i.e. a failure raised in ImportActivity reaches MainActivity through the PreResolved envelope, not just failures raised in the coordinator"
  - "the persisted sourceUri is capped at 2048 chars for an over-long content URI"
  - "a provider that throws a RuntimeException from resolveAndOpen still yields exactly one outcome (Unreadable) and does not abort the batch"
  - "PERMIT LEAK: after a batch mixing Ready, PreResolved, a thrown exception, and a mid-loop scope cancellation, outstanding permits return to zero (a 21st import still admits)"
acceptance:
  - "All ten connected tests GREEN on the emulator."
  - "The one-outcome-per-URI invariant holds: a mixed batch containing every failure class emits outcomes == inputs."
  - "No new Compose surface is introduced; #2030 is cited in the PR body."
gate: |
  ANDROID_CMD="cd android && ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.imports.IncomingIntentImportConnectedTest" ANDROID_SERIAL=emulator-5554 scripts/run-android-tests.sh
  # ONE test class per connected run; never drive the emulator while this is in flight.
```

### WI-6 — Gate-5 acceptance pass + evidence (behavioral, ~90 LOC + docs)

```yaml
id: feat:#155/WI-6
tier: behavioral
depends: [feat:#155/WI-5]
platform: android-app
bump_tier: patch
writes:
  - android/app/src/androidTest/kotlin/com/vreader/app/imports/IncomingIntentFormatMatrixConnectedTest.kt
  - dev-docs/verification/feature-155-<YYYYMMDD>.md
spec: |
  FIXTURE POLICY (AGENTS.md "real books first"; test-books/books/ contains azw3/, epub/, txt/ ONLY —
  there is NO real PDF and NO real MD book in this repo):
    EPUB, TXT, AZW3  -> REAL books from test-books/books/. requireNotNull the fixture; NEVER let the
                        test pass by falling back to a synthetic substitute.
    PDF, MD          -> synthetic, under the EXPLICIT AGENTS.md exception "the format has no real
                        book (no real PDF or MD today)". State the exception in the evidence file.
    malformed matrix -> synthetic by necessity (no real book is zero-byte / truncated / mislabelled).
  Re-push fixtures every run: the connected task wipes /sdcard/Android/data/<pkg>/.
  ALSO re-run every connected class WI-5 added. Connected tests merged during earlier WIs are
  UNVERIFIED until they actually run; fix anything RED before anything flips to VERIFIED. Prefer
  compose.waitUntil polling over waitForIdle for anything debounced.
  RELEASE REACHABILITY (rule 47:90; round 2, H5). app/build.gradle.kts has NO buildTypes block and NO
  signingConfig, so assembleRelease yields an UNSIGNED APK that cannot be installed — "install the
  release build" is not available. Discharge the clause with a static half plus a dynamic half:
    STATIC (release artifacts): run :app:processReleaseManifest and :app:assembleRelease; show
      ImportActivity + all four filters + exported="true" in
      app/build/intermediates/merged_manifests/release/AndroidManifest.xml AND in `aapt2 dump xmltree`
      over the release APK; DIFF the release and debug merged <activity .imports.ImportActivity>
      blocks and show they are IDENTICAL (sound because app/src/debug contributes no intent-filter — F1).
    DYNAMIC (installed debug build, whose relevant manifest was just shown identical): the DocumentsUI
      "Open with" chooser drive plus `cmd package query-activities` against the real PackageManager.
  Both halves go in the evidence file; neither alone is sufficient.
tests:
  - "all 5 formats import via a VIEW intent (real for EPUB/TXT/AZW3, synthetic-by-exception for PDF/MD)"
  - "malformed matrix: zero-byte, truncated EPUB, lying extension (.txt holding a PDF), 14MB+ large file"
  - "SEND and SEND_MULTIPLE passes, incl. a partial batch where some items are unsupported"
  - "re-run of IncomingIntentImportConnectedTest AND ImportFilterResolutionConnectedTest — all GREEN"
acceptance:
  - "Evidence file names the PRODUCTION user path taken ('Files -> long-press -> Open with -> VReader') and includes BOTH halves above: the release merged-manifest + aapt2 xmltree output and the debug/release manifest diff; and the DocumentsUI chooser screenshot plus `cmd package query-activities` output."
  - "The fixture-policy exception for PDF/MD is stated explicitly in the evidence file."
  - "device_or_simulator records the AVD."
gate: |
  ANDROID_CMD="cd android && ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.imports.IncomingIntentFormatMatrixConnectedTest" ANDROID_SERIAL=emulator-5554 scripts/run-android-verify.sh
  ANDROID_CMD="cd android && ./gradlew :app:assembleRelease :app:processReleaseManifest" scripts/run-android-tests.sh
```

**Dependency graph.** WI-1 ‖ WI-2 (disjoint write-sets — and no WI writes `version.properties`, so the
disjointness is real). WI-3 → WI-4 → WI-5 (joining WI-2) → WI-6. `ImportActivity.kt` is written by
WI-2 (skeleton) and WI-5 (body), and `strings.xml` by both, so **WI-2 and WI-5 must never run
concurrently** — the graph already serialises them.

**Rule-55 dispatch note.** Five WIs create new Kotlin files; unlike iOS there is no `project.pbxproj`
to regenerate (Gradle source-set globs pick them up), so rule 55's "new files are not dispatchable"
degrade — an xcodegen constraint — does not apply. Android lanes still dispatch at **width 1** (single
shared emulator).

---

## 11. Test catalogue

**JVM (Robolectric / JUnit) — `android/app/src/test/kotlin/com/vreader/app/`**

| File | Covers |
|---|---|
| `data/BookImporterTest.kt` (extended) | WI-1: format override, null-default equivalence, key equality. |
| `imports/ImportIntentFilterTest.kt` | **Structural only** — four filters with the expected actions/categories/mimeTypes/schemes; `content`-only filter B; `MainActivity` unchanged. Robolectric's resolver is a shadow, so this test deliberately does **not** claim to prove matching (round 2, M4). |
| `imports/ImportActivityUriExtractionTest.kt` | `urisFrom` for VIEW / SEND / SEND_MULTIPLE; **ClipData-only** payload; missing/wrong extra; `MAX_BATCH`; empty. |
| `imports/IncomingBookResolverTest.kt` | The D3 chain in order; extension-beats-sniff invariant; octet-stream/`*/*`/null contribute nothing; name fallbacks; **exactly one `openInputStream` per `resolveAndOpen`**, stream closed on `UnsupportedFormat`; `sanitizeDisplayName` (newline, NUL, 10k chars, CJK, RTL, and each of U+061C/U+200E/U+200F/U+202E); `peek` SIZE parsing; a `ContentResolver` throwing `SecurityException` on `query`. |
| `imports/BookMagicSnifferTest.kt` | PDF / stored-mimetype EPUB / BOOKMOBI / UTF-8 / UTF-16 / random binary; **deflated first entry → null**, **first entry not `mimetype` → null**, **non-zero extra length → null**, **declared size ≠ 20 → null**, truncated header → null, bomb-shaped input never inflated; stream preservation; non-mark-supporting stream; zero-byte; short input. |
| `imports/IncomingImportCoordinatorTest.kt` | **Process-wide** sequencing across interleaved `enqueue` calls; `PreResolved` relay ordering; late-collector delivery; `wasAlreadyPresent`; **two-scope** cancellation; failure isolation; **stream closure on every path**; counting-guard cap with absent/lying size; infinite stream; **the stall-interrupt (a blocking `read` unblocked by the watchdog's `close()`)**; `MAX_IN_FLIGHT` rejection; revoked-grant `SecurityException`; aged-vs-fresh `.part` sweep. |

**Connected (emulator) — `android/app/src/androidTest/kotlin/com/vreader/app/imports/`**

| File | Covers |
|---|---|
| `ImportFilterResolutionConnectedTest.kt` | WI-2: the **authoritative** filter-matching matrix on a real device `PackageManager` — positive resolutions, the `SEND`+`image/jpeg` negative, and every empirical `pathPattern` case (round 2, M4). |
| `IncomingIntentImportConnectedTest.kt` | WI-5's twelve cases: VIEW→one row→Library; duplicate→no second row; unsupported→toast (via the `PreResolved` envelope); `EXTRA_TEXT`-only→silent finish; own-fileprovider rejection; warm start (exactly one `MainActivity`); cold start; import completing after `ImportActivity` is destroyed; capped `sourceUri`; provider throwing `RuntimeException`→exactly one `Unreadable`; permit-leak zero-balance after a mixed batch; and the one-outcome-per-URI total-invariant batch. |
| `IncomingIntentFormatMatrixConnectedTest.kt` | WI-6: 5 formats under §10's fixture policy; malformed matrix; 14MB+; SEND / SEND_MULTIPLE; partial batch. |

**Note on the storage-full test** (round 1, M10). `BookImporter` owns its file I/O and no filesystem
seam is introduced, so "storage full" is **not** tested by a throwing sink. It is covered two ways
that are actually reachable through the declared API: the **free-space preflight** (`usableSpace` is
injectable via `booksDir`, WI-4) and an **`IOException` thrown mid-read** by a test `InputStream`,
which exercises the same `Failed` + temp-cleanup path.

**Connected-test discipline (binding).** Connected tests merged during a foundational WI are
**unverified until they run** (the #133 recurrence). WI-6 budgets a pass to run every connected class
WI-5 added and fix anything RED before `VERIFIED`. One test class per connected run.

---

## 12. Backward compatibility

- **Existing rows are untouched.** Identity is `format:sha:bytes` (F4) and resolution is
  extension-first (D3), so a book already imported via SAF keeps its key and re-arrives from an intent
  as the same row via the author-preserving upsert (F5).
- **Scope of that guarantee (narrowed at round 1, H7).** It holds for **extension-bearing** inputs
  (D3 steps 1–2), which is every SAF import and the overwhelming majority of intents. It does **not**
  hold for a *nameless* Markdown file: no magic distinguishes Markdown from plain text, so the sniffer
  never returns `md` and such a file resolves to `txt` — a different key from the same bytes imported
  as `notes.md`, hence a second row. Accepted as a Low (§13) with a dedicated test documenting the
  behaviour; the alternative (guessing `md` from content) would misclassify ordinary text files and
  make the problem symmetric and worse.
- **`importStream` stays source-compatible** — one trailing defaulted parameter; every existing call
  site — `LibraryViewModel.kt:182`, `RestoreImporter.kt:168`, **and `OpdsAcquisitionService.kt:38`**
  (the complete set, verified by `grep -rn importStream android/app/src/main/kotlin/`; WI-1 owns this
  inventory) — compiles and behaves unchanged. WI-1 re-greps the
  full set before editing.
- **No Room schema change**, so no migration and no `VReaderDatabaseMigrationTest` delta.
- **Backup/restore format unchanged** — no new persisted field. `sourceUri` continues to hold
  provenance only (`BookImporter.kt:101`), now length-capped; nothing reads it back.
- **`contracts/` and `:identity` untouched**, so the iOS↔Android conformance lane is unaffected.
- **Downgrade**: an older APK simply lacks the filters; books imported by a newer build stay readable.

---

## 13. Known limitations (accepted)

1. **No import feedback UI** — in-progress, added, already-in-library, unsupported. Blocked on
   `needs-design` **#2030** (§7). Matches iOS's shipped behaviour.
2. **Share-sheet breadth** — accepting `text/plain` and `application/octet-stream` on `SEND` (D4) puts
   VReader in the share sheet for text snippets and arbitrary binaries. Accepted deliberately: the
   runtime `EXTRA_TEXT`-only guard makes the snippet case a silent no-op, and the alternative broke
   real `.txt`/`.md`/octet-stream file shares.
3. **A lying extension is not corrected** — identity stability wins (D3, R12).
4. **A nameless Markdown file imports as `txt`** — §12; no magic distinguishes them.
5. **Titles come from the file name**, not EPUB metadata (F9). `BookOpener.readMetadata` is a named
   follow-up.
6. **Filter B rarely fires** — most senders set a type and most `content://` paths carry no filename
   (§4). Retained for the typeless provider-path case at near-zero cost.
7. **No persistable URI permission** — VReader copies at import and never re-reads the source.
8. **`MAX_IMPORT_BYTES = 512 MiB`** rejects a legitimately enormous book. No fixture approaches it;
   the bound exists because the entry point is exported and untrusted (D8).
9. **A failure *toast* can still be lost in a collector handover.** The buffered `Channel` (D9)
   eliminates the no-collector (cold-start) loss, but `receiveAsFlow` is single-consumer, so an
   outcome received microseconds before a rotation tears the collecting scope down is gone. Accepted:
   the lost artifact is advisory only — library state is correct either way — the same race exists on
   the shipped SAF path, and durable delivery belongs to #2030's surface.
10. **The release variant cannot be installed** (no `buildTypes`/`signingConfig` in
    `android/app/build.gradle.kts`), so Gate-5's release evidence is static (merged manifest + `aapt2
    dump xmltree` + a debug↔release manifest diff) with the traversal proven on the debug install
    (§8). Adding a release signing config is out of scope for this feature.

---

## 14. Revision history

| Round | Date | Auditor | Verdict | Open C/H/M | Outcome |
|---|---|---|---|---|---|
| v1 | 2026-08-04 | — | — | — | Initial plan (Gate 1). |
| Gate-2 r1 | 2026-08-04 | Codex `gpt-5.5` / high (`scripts/run-codex.sh`, rule 53) | **BLOCK** | C=0 **H=9 M=10** L=0 | All 19 findings addressed in v2 — see §14.1. |
| Gate-2 r2 | 2026-08-04 | Codex `gpt-5.5` / high | **BLOCK** | C=0 **H=5 M=7** L=0 | 14/19 round-1 fixes confirmed REAL, 5 PARTIAL; all 12 open findings addressed in v3 — see §14.2. |
| Gate-2 r3 | 2026-08-04 | Codex `gpt-5.5` / high | **BLOCK** | C=0 **H=3 M=1** L=4 | 8/12 round-2 fixes confirmed REAL, 4 PARTIAL. All 8 findings addressed in v4 — see §14.3. Rule 47's 3-round cap reached → escalated to the user. |
| Gate-2 r4 | 2026-08-04 | Codex `gpt-5.5` / high | **BLOCK** | C=0 **H=3 M=1** L=2 | **SANCTIONED OVERRIDE of rule 47's 3-round cap** — see §14.4. 4/8 REAL (all Lows), 4 PARTIAL. **Every remaining finding is one defect class: the decision sections were fixed, the WI Spec blocks were left stale.** Fixed in v5 — see §14.5. **Terminal: no fifth round; Gate 2 is NOT certified clean and returns to the user.** |

### 14.1 Gate-2 round 1 — findings and disposition

Artifact: `<scratchpad>/f155-gate2-r1.txt`. Verdict `BLOCK — C=0 H=9 M=10 L=0`.

| # | Sev | Finding | Disposition in v2 |
|---|---|---|---|
| 1 | HIGH | `CLEAR_TOP|SINGLE_TOP` does not reuse `MainActivity`: an externally-started activity runs in the **sender's** task. | **Fixed** — `NEW_TASK or CLEAR_TOP or SINGLE_TOP`, plus `taskAffinity=""`; warm-task test asserts one instance (D2, WI-5). |
| 2 | HIGH | R3's open-fd mitigation was not implemented: `enqueue(uris)` opens *after* the grant dies. | **Fixed** — `enqueue(items: List<PendingImport>)` with already-open streams; explicit ownership (D6, WI-4/5). |
| 3 | HIGH | A non-replaying `SharedFlow` drops outcomes during cold start / rotation. | **Fixed** — buffered `Channel` + `receiveAsFlow()`, matching the shipped precedent F11b (D9). |
| 4 | HIGH | Excluding `text/plain` + `octet-stream` from `SEND` breaks real file shares and contradicted WI-6. | **Fixed** — both accepted on `SEND`; discrimination moved to a runtime `EXTRA_TEXT`-only guard; cost accepted (D4, §13.2). |
| 5 | HIGH | No byte cap or timeout: a hostile provider can fill storage. | **Fixed** — `SIZE` preflight, free-space preflight, counting guard, 5-min timeout, `TooLarge` outcome (D8, R10). |
| 6 | HIGH | WI-6 demands real books for all 5 formats, but no real PDF/MD fixture exists. | **Fixed** — verified independently (F20); WI-6 uses real EPUB/TXT/AZW3 and cites the AGENTS.md "no real book exists" exception for PDF/MD. |
| 7 | HIGH | The backward-compat guarantee was too broad (nameless Markdown → `txt` → different key). | **Fixed** — guarantee narrowed to extension-bearing inputs; sniffer never returns `md`; accepted Low with a test (§12, §13.4). |
| 8 | HIGH | Write-sets omit `android/version.properties`, so WI-1 ‖ WI-2 disjointness was false. | **Fixed** — rule 40 batch mode: the orchestrator allocates the version at the merge slot; lanes carry `bump_tier` only (§5). |
| 9 | HIGH | `gate:` commands omit `ANDROID_CMD` (the wrapper defaults to the spike harness) and WI-2 used raw `adb`. | **Fixed** — verified independently (F19); every gate spells out `ANDROID_CMD="cd android && ./gradlew :app:…"`; device steps run under `run-android-verify.sh` (§8). |
| 10 | MED | `file://` has an empty authority, so `host="*"` cannot match it. | **Fixed** — filter B is `content`-only; `file` stays only in the MIME filter; rationale recorded (§4). |
| 11 | MED | `Theme.NoDisplay` is unsafe with pre-finish work. | **Fixed** — translucent non-`NoDisplay` theme (D2). |
| 12 | MED | EPUB sniffing parses attacker-controlled ZIP structure. | **Fixed** — D7: first-local-header-only, buffer-bounded, no ZIP library, never inflates. |
| 13 | MED | Hostile `displayName` still becomes the title; `sourceUri` persisted raw. | **Fixed** — `sanitizeDisplayName` (control + bidi strip, NFC, cap) and a `sourceUri` cap (R8, WI-3). |
| 14 | MED | The `.part` sweep can race a live import. | **Fixed** — once at container construction before the importer is reachable, age-gated to >1 h (R4, WI-4). |
| 15 | MED | "Survives cancellation" was ambiguous about *which* scope. | **Fixed** — caller = `ImportActivity.lifecycleScope`, copy = `appScope`; two distinct `TestScope`s in the test (WI-4). |
| 16 | MED | `docs/architecture.md` deferred to WI-6 despite a new exported component landing in WI-2. | **Fixed** — moved into WI-2's write-set. |
| 17 | MED | Spec blocks were not standalone (referred to §4/D3/F7/§8). | **Fixed** — every Spec block now inlines the filters, the full MIME map, the resolution chain, stream-ownership and scope rules, and the evidence requirements. |
| 18 | MED | `urisFrom` missed `ClipData`-only payloads. | **Fixed** — ClipData fallback + tests (WI-2). |
| 19 | MED | "Storage-full via a throwing sink" is not testable with the current API. | **Fixed** — claim replaced by the free-space preflight plus a mid-read `IOException`; no fictional seam (§11 note). |

### 14.2 Gate-2 round 2 — findings and disposition

Artifact: `<scratchpad>/f155-gate2-r2.txt`. Verdict `BLOCK — C=0 H=5 M=7 L=0`. The auditor
independently regression-checked all 19 round-1 dispositions: **14 REAL**, **5 PARTIAL**
(R1-3, R1-5, R1-9, R1-12, R1-13); none ABSENT.

| # | Sev | Finding | Disposition in v3 |
|---|---|---|---|
| 1 | HIGH | Every gate used `./gradlew` from the repo root, but only `android/gradlew` exists. | **Fixed** — verified independently (`ls gradlew` → No such file); all 8 gate commands are now `ANDROID_CMD="cd android && ./gradlew …"` (§8 note). |
| 2 | HIGH | `withTimeout` cannot interrupt a blocking `InputStream.read`, so the timeout was nominal. | **Fixed** — D8: a watchdog closes the fd on a 5-min total / 60-s stall, which is what unblocks the read; `withTimeoutOrNull` only advances the worker. Named stall test in WI-4. |
| 3 | HIGH | Resolver/open failures occur in `ImportActivity`, but the coordinator accepted only successes — `Unsupported`/`Unreadable` could never reach `outcomes`. | **Fixed** — `IncomingItem = Ready | PreResolved` envelope; the coordinator relays pre-resolved failures in order, one outcome per input URI (D6, WI-4, WI-5). |
| 4 | HIGH | Sequencing and `MAX_BATCH` were per-`enqueue`, not process-wide across concurrent `ImportActivity` instances. | **Fixed** — one process-wide queue drained by one worker; `MAX_IN_FLIGHT = 20` process-wide, distinct from the per-intent `MAX_BATCH`; concurrent same-key safety noted from `createTempFile` + `ATOMIC_MOVE` (R9, WI-4). |
| 5 | HIGH | Gate-5 ran only debug instrumentation; release reachability unproven. | **Fixed** — established that the project has **no `buildTypes`/`signingConfig`**, so release cannot be installed; evidence split into a static release half (merged manifest + `aapt2 dump xmltree` + debug↔release diff, sound because `app/src/debug` adds no filter — F1) and a dynamic debug half (§8, WI-6, §13.10). |
| 6 | MED | `resolve()` + `openStream()` opened two streams — TOCTOU and one-shot-provider risk. | **Fixed** — a single `resolveAndOpen(uri)` opens one stream, sniffs via mark/reset, returns it rewound; `peek(uri)` covers the metadata-only preflight (D6, WI-3). |
| 7 | MED | "Reject before opening" sat in the coordinator, i.e. after the stream was already open. | **Fixed** — D8 splits ownership: declared-size + free-space rejection in `ImportActivity` *before* opening (cursor queries); the counting guard is the post-open backstop (WI-5 step 3b). |
| 8 | MED | The `Channel` still loses an outcome consumed by a dying collector on rotation. | **Fixed by scoping the claim** — D9 now guarantees only the no-collector case and records the handover race as an accepted Low (§13.9) with rationale. |
| 9 | MED | `ImportIntentFilterTest` is Robolectric, so it cannot prove real `pathPattern`/manifest matching. | **Fixed** — the JVM test is demoted to a structural check; the authoritative matrix moves to a new connected `ImportFilterResolutionConnectedTest`, backstopped by `cmd package query-activities` in WI-6 (WI-2, §11). |
| 10 | MED | EPUB sniffing omitted the OCF extra-length-zero and size-==-20 checks. | **Fixed** — D7/WI-3 now require extra length 0 and compressed == uncompressed == 20, with negative tests. |
| 11 | MED | Bidi stripping omitted U+061C, U+200E, U+200F. | **Fixed** — the full Bidi_Control set is enumerated in WI-3, with a per-code-point test. |
| 12 | MED | The `sourceUri` cap was declared but never applied. | **Fixed** — WI-5 step 4 specifies `uri.toString().take(2048)` at the assignment, with a connected test. |

### 14.3 Gate-2 round 3 — findings, disposition, and escalation

Artifact: `<scratchpad>/f155-gate2-r3.txt`. Verdict `BLOCK — C=0 H=3 M=1 L=4`. Regression check of the
12 round-2 dispositions: **8 REAL**, **4 PARTIAL** (R2-2, R2-3, R2-4, R2-12), none ABSENT.

| # | Sev | Finding | Disposition in v4 |
|---|---|---|---|
| 1 | HIGH | `MAX_IN_FLIGHT` could not bound open fds: `ImportActivity` opens up to `MAX_BATCH` streams *before* `enqueue`, so concurrent activities exceed the cap before the coordinator sees anything. | **Fixed** — `tryAcquireSlot()`/`releaseSlot()` permits (`Semaphore(MAX_IN_FLIGHT)`) acquired **before** each `resolveAndOpen`; a refused permit yields `PreResolved(Failed)` with nothing opened (§5, WI-5 step 2b, WI-4 permit-leak test). |
| 2 | HIGH | The stall fix assumed a cross-coroutine `close()` always unblocks a parked `read`; untrue for some provider/file/asset fd shapes. | **Fixed by splitting the claim** — D8 now separates a *guaranteed* queue-liveness property (per-item thread + `withTimeoutOrNull`; the worker advances regardless, costing at most one leaked thread) from a *best-effort* thread-release (close + interrupt), and notes the watchdog cannot race a successful copy. JVM liveness test + a **connected** stall case in WI-6. |
| 3 | HIGH | The one-outcome-per-URI invariant still had zero-outcome branches (the fileprovider guard rejected before creating an item; `peek` exceptions were uncaught). | **Fixed** — WI-5 step 2a emits `PreResolved(Unreadable)` for the guard, 2c wraps `peek` in try/catch, and step 3 states the invariant as total with a mixed-failure-class test asserting `outcomes == inputs`. |
| 4 | MED | The `sourceUri` cap had no data path: `PendingImport` carried only `uri`, and WI-5 never calls `importStream`. | **Fixed** — `PendingImport.sourceUri: String` holds the already-capped value (§5), computed at WI-5 step 2e and passed by the coordinator as `importStream(sourceUri = …)`. |
| 5 | LOW | Stale §4 text still said the Robolectric test drives the real `PackageManager`. | **Fixed** — §4 now names `ImportFilterResolutionConnectedTest` as authoritative and the JVM test as structural. |
| 6 | LOW | `IncomingMetadata` was used but never defined; `ResolvedIncomingBook` was stale. | **Fixed** — `IncomingMetadata` defined; the unused DTO removed. |
| 7 | LOW | WI-1's call-site inventory omitted `OpdsAcquisitionService.kt:38`. | **Fixed** — verified independently (`grep -rn importStream` → 3 production callers); all three enumerated. |
| 8 | LOW | WI-5 said "eight connected tests" while listing ten. | **Fixed** — corrected to ten. |

### 14.4 Round 4 — sanctioned override of rule 47's 3-round cap

**This is an explicit, authorized exception, not a precedent that the cap is advisory.** Rule 47 Gate 2
says "Maximum 3 audit rounds. If unresolved findings remain after round 3, stop and escalate to the
user — accept, defer, or redesign." Round 3 was escalated as required (§14.3 below) and the user chose
option (b): **one confirming round, scoped strictly to the eight v4 deltas.**

**Reason for the override (recorded so the decision is auditable):** three of the four PARTIALs in
round 3 were of the "**the fix moved the problem**" class — a fix that satisfies the letter of a
finding while relocating its cause (r3's `MAX_IN_FLIGHT` cap moved *behind* the point where fds are
opened; the stall fix moved an unreliable mechanism from `withTimeout` to `close()`; the one-outcome
invariant kept acquiring new zero-outcome branches). That churn signal, not the raw finding count, is
what justifies spending a further round: an unconfirmed v4 is most likely to fail in exactly the way
v2 and v3 did. The same override was granted on feature #139 earlier today for the same signal, where
the extra round found the scheme unsound rather than rubber-stamping it.

**Terms of the override** — the scope is what keeps this from becoming an open-ended loop:

- **In scope**: (1) the eight v4 fixes, each interrogated for "did this move the problem rather than
  solve it?"; (2) any NEW internal contradiction the surgical v4 edits introduced — the defect class
  these rewrites kept producing.
- **Explicitly out of scope, already settled, not to be re-litigated**: the post-import decision (D1),
  the WI split, the `needs-design` #2030 filing, and the release-signing / Gate-5 evidence split.
- **Terminal either way**: zero open C/H/M → Gate 2 is marked **clean** and Gate 2 ends. Any finding
  remaining → stop and report with an accept / defer / redesign recommendation. **No fifth round.**

### 14.5 Gate-2 round 4 — findings, disposition, and the terminal recommendation

Artifact: `<scratchpad>/f155-gate2-r4.txt`. Verdict `BLOCK — C=0 H=3 M=1 L=2`. Regression check of the
eight v4 deltas: **4 REAL** (r3-5 … r3-8, all the Lows), **4 PARTIAL** (r3-1 … r3-4), none ABSENT.

**The finding that matters is the shape of the findings.** All four PARTIALs, and all six open items,
are a *single* defect class — and it is not a design defect:

> The v4 edits corrected the **decision sections** (D6, D8, §5's signatures) and the auditor accepts
> them; what they failed to do is **propagate those corrections into the machine-readable WI Spec
> blocks**, which still carried the superseded v3 framing. Round 4 is literally citing D8 as the
> standard that WI-4 fails to meet, and §5's `PendingImport` as the standard WI-4's copy fails to
> match.

That matters because, under rule 55, the Spec block — not the prose — is what a lane actually
receives; a stale Spec block would be implemented verbatim. So these were real defects worth
catching, and they were also mechanical to close.

| # | Sev | Finding | Disposition in v5 |
|---|---|---|---|
| 1 | HIGH | Permit ownership is not exception/cancellation-safe between acquire and enqueue; 20 leaks would permanently wedge admission. | **Fixed** — WI-5 step 2b now specifies a `try/finally` spanning the rest of each URI's block with an explicit `transferred` flag: ownership passes to the coordinator **iff** a `Ready` item reaches `enqueue()`; every other exit (PreResolved, throw, `CancellationException` mid-loop) releases in the `finally`. Invariant "outstanding permits return to 0 after any batch" plus a connected leak test. |
| 2 | HIGH | WI-4 still said "the close is what makes the timeout real", contradicting D8's guaranteed worker-advances-regardless design. | **Fixed** — WI-4's timeout paragraph rewritten to D8's two-tier framing: the *guarantee* is per-item thread + `withTimeoutOrNull` (worker advances, permit released, unconditionally); close/interrupt is explicitly *best-effort*. Also resolves the cap interaction the auditor asked about: the permit is released when the **worker** gives up, not when the thread dies, so leaked threads cannot wedge admission. The test is required to fail if liveness depended on `close()`. |
| 3 | HIGH | `resolveAndOpen`'s enumerated exception mapping let a hostile provider's `RuntimeException` escape and produce zero outcomes. | **Fixed** — WI-5 step 2f is now a **total** mapping: rethrow `CancellationException`, map `UnsupportedFormat`, then `catch (e: Throwable) -> PreResolved(Unreadable)`. Rationale recorded (the provider is attacker-controlled, so the throwable set is not knowable) plus a `RuntimeException` test. |
| 4 | MED | WI-4's `PendingImport` shape omitted `sourceUri` and never required `importStream(sourceUri = …)`, contradicting D6/WI-5. | **Fixed** — `sourceUri` added to WI-4's `PendingImport`, with an explicit requirement to pass it **verbatim** and never re-derive from `uri.toString()` (which would discard the cap), plus a spy-importer test. |
| 5 | LOW | §12's compat sentence still listed only two `importStream` call sites. | **Fixed** — all three enumerated (`LibraryViewModel.kt:182`, `RestoreImporter.kt:168`, `OpdsAcquisitionService.kt:38`). |
| 6 | LOW | §11 said "ten cases" while enumerating nine. | **Fixed** — the list is now explicit and the count (twelve, after v5's two additions) matches it. |

**Terminal status and recommendation.** Per the override's terms there is **no fifth round**, so v5's
six fixes are applied but **unaudited**, and Gate 2 is **not certified clean**. The recommendation is
**accept and proceed to Gate 3**, for reasons specific to what round 4 actually found:

- **Zero Critical across all four rounds**, and the *design* is now explicitly endorsed by the
  auditor — round 4 used D8 and §5 as the correctness standard rather than disputing them.
- **The remaining work was propagation, not redesign.** Every v5 edit copies already-audited text from
  a decision section into the Spec block that restates it. No open question of design remains.
- **The churn signal that justified the override has resolved.** Rounds 2 and 3 produced
  "the fix moved the problem" defects; round 4's are "the fix did not reach the second place the
  same thing is written" — a strictly weaker and self-limiting class, and one Gate 3's RED tests
  would catch immediately (each is now an explicitly named failing test).
- **Residual risk is bounded and named**: if a v5 Spec block is still inconsistent, the cost is one
  lane rework at Gate 3, not a wrong design — and the Gate-4 implementation audit re-reads these
  files against the plan anyway.

Deferring or redesigning is **not** recommended: nothing structural is in question, and a further
round would re-audit text this loop has already validated twice.

### 14.3 Gate-2 round 3 — escalation record

**Escalation (rule 47 Gate 2, "Maximum 3 audit rounds").** The cap is reached. The trend is
converging (H: 9 → 5 → 3; C: 0 throughout; no finding was ever ABSENT on re-check), and every round-3
finding has a concrete fix applied above — but **v4 has not itself been audited**, so Gate 2 is **not
certified clean**. Per the rule this is the user's call:

- **(a) Accept** — treat v4's fixes as sufficient and enter Gate 3. Defensible: all 8 were narrow and
  mechanically verifiable, 4 were Low, and the three Highs are now specified rather than assumed.
- **(b) Authorize one confirming round** — a 4th audit scoped *only* to the eight v4 deltas. Cheapest
  path to a genuine PASS; recommended, since three of the four PARTIALs in round 3 were exactly the
  class of "the fix moved the problem" defect a confirming round is good at catching.
- **(c) Redesign** — not indicated; nothing structural is in question.

Until the user chooses, the row stays at Gate-2-in-progress and does **not** advance to `PLANNED`.
