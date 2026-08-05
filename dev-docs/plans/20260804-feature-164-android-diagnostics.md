# Feature #164 — Android diagnostics: log capture + viewer + export

- **Tracker row**: `docs/features.md` line 217 (`| 164|`), parity phase 4, box **G8**, Medium.
- **iOS parity source**: feature #96 (`vreader/Services/Diagnostics/`, `vreader/Views/Settings/Diagnostics/`).
- **Design (rule 51 source of truth)**: `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`,
  `diagnostics-artboards.jsx`, `VReader Diagnostics Canvas.html` (issue #1597, COMMITTED).
- **Hard dependency — a TWO-LINK chain, not one** (corrected at Gate-2; v1 mis-cited this):
  **#164 `VERIFIED` ⇐ #171 `DONE` ⇐ GH #2018 design delivered.**
  - **#171** = tracker row `docs/features.md:223` (Android Settings hub + production entry-point
    wiring). Its status is **`TODO`** — not `PLANNED`, so it has not itself passed Gate 1/Gate 2 —
    it has **no `GH: #N` mirror**, and its Notes carry **`BLOCKED: needs-design (#2018)`**.
  - **GH #2018** is *not* #171's mirror — it is the rule-51 design issue
    *"Design needed: Android Settings hub + Library entry point (unblocks features #114, #118, #120,
    #122)"*, labels `enhancement` + `needs-design`, state OPEN.
  - So WI-8/WI-9 are blocked on a feature that is itself blocked on a design **that does not yet
    exist**. This is an indefinite block, not a scheduling slip — see §9 R9.
  See "Reachability" — this feature **cannot reach `VERIFIED` until that whole chain resolves**.
- **Platform**: `android-app` (rule 40 → bump `android/version.properties`; rule 47 Gate-5 Android tier).

---

## 1. Problem

A user hits a bug on Android — an import fails, a WebDAV backup dies, an AZW3 book renders blank,
an AI provider call 401s. Today there is **no way for them to tell us what happened**. Android has:

- **No in-app diagnostics of any kind.** Verified: no `diagnostics` package anywhere under `android/`.
- **6 production logging call sites, total** — all `Log.w`, no facade
  (`PdfDocument.kt:101`, `ReaderActivity.kt:756`, `FoliateBridge.kt:93`, `BookShareIntent.kt:48` and
  `:76`, `SearchIndexCoordinator.kt:157`). `identity/src/main` has zero.
- **No redaction utility.** `grep -rni redact android/` → zero hits. The only PII protection is
  eight `// never logged` comments, of which just **two** sit adjacent to a credential-header write
  (`OpenAiCompatibleProvider.kt:35` Authorization, `AnthropicProvider.kt:32` x-api-key); the other
  six are file/class header comments. I.e. the protection is a convention, not a mechanism.

So the current bug-report loop is "reproduce it on the maintainer's emulator or it didn't happen."
iOS solved this in #96: capture runtime log entries, show them in a designed viewer with
level/category filters, and export a **redacted** plain-text file through the share sheet. #164 is
that capability for Android.

The user-facing outcome: **"Settings → Diagnostics → share"** is a scriptable instruction we can put
in a bug-report template, and what comes back is a PII-safe text file.

---

## 2. Platform feasibility — the load-bearing question, tested not assumed

The plan's whole content pipeline rests on one claim: **can a non-privileged Android app read its own
log entries back?** `READ_LOGS` is `signature|privileged` and is not grantable to third-party apps, so
this is not obvious. It was **tested on the live emulator**, not reasoned about.

### Evidence (emulator `emulator-5554`, `ro.build.version.sdk=35`, Android 15, AOSP `sdk_gphone64_arm64`)

| # | Test | Result |
|---|---|---|
| 1 | `run-as vreader.spike log -p i -t VRDIAG164 "hello-…"` then `run-as vreader.spike logcat -d -t 200 \| grep -c VRDIAG164` | **1** — the app uid read back its own line |
| 2 | control: same line via shell uid `logcat -d` | 1 — line really was written |
| 3 | write as **shell** uid (`log -t VRDIAGSHELL`), read as **app** uid | **0** — app cannot see other uids |
| 4 | same line read as shell uid | 1 — line really was written |
| 5 | `logcat -g` | `main`, `system`, `crash`, `kernel` = **2 MiB** ring each; max entry 5120 B, max payload 4068 B |
| 6 | `logcat -d -v uid -v threadtime -v year -v UTC -t 3` | `2026-08-04 03:58:03.538 +0000  1000   570   733 W BestClock: …` — uid column present, deterministic parse |
| 7 | `run-as vreader.spike logcat -d -v uid -v threadtime` | only uid `10209` rows returned |

**Conclusion (stated no more strongly than the evidence supports)**: under `run-as` at API 35, reads
are **uid-filtered** — the reader saw its own entry and not another uid's. That is what tests 1–4/7
establish. They do **not** establish that an unprivileged `untrusted_app` is *permitted* to open a
reader connection at all; permission and filtering are separate questions and only the latter is
proven here. The permission question is left **entirely** to WI-1's connected test.

**Which caveat is the real one** (sharpened at Gate-2 — v1's reasoning was loose). `run-as` carried
supplementary groups `1007 log` / `1011 adb` that a real app lacks, and the obvious worry is that
group membership alone explains the successful read. **Tests 3 and 7 discriminate against that
hypothesis**: logd grants an *unfiltered* stream to a client holding `AID_LOG(1007)`, yet our reader
saw only its own uid — so it was *not* being treated as a privileged log client, and the observed
behavior is genuine uid filtering rather than a group grant. The residual risk is therefore **not**
the groups; it is **SELinux policy**: `runas_app` and `untrusted_app` are different domains, and the
concrete untrusted_app failure modes are (a) `unix_stream_socket connect` to logd's `logdr` socket,
and (b) `execute` on `/system/bin/logcat` (a `system_file`). Those are exactly what WI-1's connected
test exercises, and naming them is what makes that test a real gate rather than a ritual. (Prior art is consistent with
it being permitted — ACRA and similar crash reporters have read own-logs this way since Android 4.1 —
but prior art is not evidence about this device/API level, and is not treated as such.)

### The honest caveat (and why WI-1 is a gate, not just a WI)

Tests 1/3/7 ran under **`run-as`**, whose SELinux domain is `runas_app` (confirmed:
`context=u:r:runas_app:s0:c209,…`) and whose supplementary groups included `1007(log)` and
`1011(adb)` — **a real app process runs as `untrusted_app` and does not carry those groups.** So the
above is strong evidence for the *platform policy* (uid filtering is a logd behavior, not a group
grant) but is **not proof for a production `untrusted_app` process**. It was also an AOSP emulator;
OEM builds vary.

Therefore:

1. **WI-1 carries a connected test that execs `logcat` from the real app process** (`untrusted_app`,
   no `run-as`), writes a line via `Log.w`, and asserts read-back. That test — not this section — is
   the acceptance evidence. If it fails, the fallback below carries the feature.
2. **The feature ships a degradation path that does not depend on logcat at all** (WI-3). This is not
   belt-and-braces padding: a source that a platform policy can revoke needs a floor.

### What the fallback actually delivers if logcat is denied (the standalone floor)

If WI-1's connected test fails, `LogcatDiagnosticsSource` reports `SourceResult.Unavailable` on every
load, `CompositeDiagnosticsSource` serves the ring alone, and the entire feature runs on
`RingBufferDiagnosticsSource`. (It reports `Unavailable`, **not** `Available(empty)` — that
distinction is what drives the export header's `capture source:` line in §6.5.) That degraded feature
must still be worth shipping, so state precisely what it is — this is not a hand-wave.

**Still captured** (everything routed through `VLog`, i.e. every deliberate vreader log call):

- All 6 migrated sites today, and every future vreader log call, with a *better* category vocabulary
  than logcat tags give (§ below).
- Caught-and-handled exceptions we choose to log, with full stack traces (`VLog.w(cat, msg, throwable)`).
- Whatever we instrument next — the ring buffer makes adding a diagnostic line a one-liner.

**Lost** (and this is the real cost):

| Lost source | Why it matters |
|---|---|
| **Readium** internal errors (EPUB parse/nav failures) | the #1 cause of "book won't open" reports |
| **WebView / Chromium console** beyond what `FoliateBridge` relays | AZW3/foliate render failures |
| **Room / SQLite** errors and slow-query warnings | corruption + migration reports |
| **`HttpURLConnection`/TLS stack traces** under WebDAV & OPDS | the "backup fails on my NAS" class |
| **ART crash traces (`FATAL EXCEPTION`)** and ANR traces | any hard crash |
| **Anything from a previous process launch** | the pre-crash trail (a logd-only capability) |

**Verdict on the degraded feature**: still shippable, but materially weaker — it becomes "vreader's own
breadcrumbs" rather than "what the device saw." It answers *our* instrumentation questions and none of
the third-party ones. That is a real feature (iOS #96's viewer over `Logger`-only output is
comparable), but the plan does **not** pretend it is equivalent.

**Therefore the decision is forced early, not at Gate 5**: WI-1's connected test is a *gate*. If it
fails, WI-1 stops and escalates to the user with this table. It is explicitly NOT the implementer's
call to quietly proceed on the floor.

#### GO / NO-GO criterion if WI-1's feasibility gate FAILS (binding, decided in advance)

Do not improvise this mid-implementation. The recommendation is pre-committed:

> **NO-GO on the full feature; REDUCE to a 3-WI "breadcrumbs" slice and DEFER the rest.**

Rationale. The feature's stated purpose (§1) is *"a user hits a bug and can tell us what happened."*
Rank the real Android bug-report classes against what survives without logcat:

| Reported symptom | Diagnosable on breadcrumbs alone? |
|---|---|
| "The app crashed" | **No** — ART `FATAL EXCEPTION` is the whole answer and it is lost |
| "The app froze" | **No** — ANR traces are lost |
| "This book won't open" | **Mostly no** — the cause is a Readium/foliate internal error we never see |
| "Backup fails on my NAS" | **Partly** — we log the outcome, not the `HttpURLConnection`/TLS cause |
| "It logged me out / AI errors" | **Yes** — our own call sites cover it |

So without logcat the viewer answers roughly **one of the five** classes people actually report, and
misses every hard-failure class — which is precisely when a user goes looking for a diagnostics
screen. A designed viewer, chip filters, day grouping, share/export and a redaction suite
(WI-4…WI-7, ~1,400 LOC) is **disproportionate** for surfacing our own 6 breadcrumbs.

**The reduced slice if the gate fails** — a CONCRETE dependency graph, not a gesture (Gate-2 M):

| Keep | Why | Adjustment needed |
|---|---|---|
| **WI-2** (redactor) | pure, reusable, valuable independently of any viewer | none — `depends: []` already |
| **WI-3** (`VLog` + ring + categories) | improves logging quality regardless; becomes the sole source | drop `depends: [WI-1]`; drop `CompositeDiagnosticsSource` (only one source remains) |
| **WI-4** (store: filter + redacted `exportText`) | the export payload lives here | `depends: [WI-2, WI-3]` (WI-1 removed) |
| **WI-7′** (writer + provider + share, MINUS the viewer wiring) | the actual "get it off the device" path | `depends: [WI-4]` (WI-6b removed); share is triggered from wherever #171 later puts it |

| Defer to a follow-up row | Why |
|---|---|
| **WI-1** | the platform source it exists to prove is unavailable |
| **WI-5, WI-6a, WI-6b** | a designed viewer with chip filters and day grouping is disproportionate for ~6 breadcrumbs |
| **WI-8, WI-9** | already blocked on the #171/#2018 chain regardless |

Re-open the deferred slice only if a supported route to the platform log appears (a `bugreport`/SAF
user-initiated capture, or shipping our own crash capture via an `UncaughtExceptionHandler` writing
into the ring — a different feature, separately designed). **Note**: even this reduced slice has no
production entry point until #171, so it too parks at `DONE`.

**Who decides**: the user, on the escalation. This paragraph is the *recommendation* the escalation
must carry, so the decision is a yes/no on a written option rather than a fresh design discussion.

### Second, independent reason the in-process source exists

The brief's framing — "an in-process ring buffer would capture almost nothing" — is true *today* and
would stay true without a facade, but it misses a design constraint: **the designed viewer has
category chips** (`Library`, `Persistence`, `Reader`, `AI`, `Sync`, …). Android logcat tags are
arbitrary strings chosen per-file (`"ReaderActivity"`, `"FoliateBridge"`, `"BookShare"`,
`"SearchIndex"`) — they are *not* a stable subsystem vocabulary, and 4 of our 6 sites would collapse
into unrelated chips. A thin `VLog` facade with a `DiagnosticsCategory` enum makes vreader's own
entries carry the design's vocabulary, **and** forwards to `android.util.Log` so logcat still sees
them. It earns its place on category quality alone; the fallback role is a bonus.

---

## 3. Reachability — this feature is capped at `DONE` until #171

**`MainActivity` hosts only `LibraryScreen` + `SearchScreen`** (+ two collection sheets); verified —
`MainActivity.kt` `setContent` contains `LibraryScreen(...)` (:96), `SearchScreen(...)` (:125),
`AssignToCollectionsSheet` (:157), `ManageCollectionsSheet` (:174), and nothing else. There is **no
Settings screen, no gear icon anywhere in production** (`grep "Icons\..*Settings|Icons\..*Gear"` on
`app/src/main` → zero). No navigation library exists; routing is `startActivity` + `rememberSaveable`
flags.

The design's Diagnostics entry (artboards **E1/E2**) is a **"Support" group row inside the Settings
sheet** — i.e. it lives on a surface that does not exist yet. That surface is **feature #171**
("Android Settings hub + production entry-point wiring", the box-G0 reachability blocker, GH #2018),
which was filed precisely because #114/#118/#120/#122 shipped `VERIFIED` with UI a user cannot open
and were demoted `VERIFIED → DONE` on 2026-08-04.

Consequences, stated plainly:

- **This plan does NOT create a Settings screen, a gear affordance, or any substitute entry point.**
  Inventing one is a rule-51 violation (undesigned surface) *and* would duplicate #171's scope.
- **This plan does NOT add a `src/debug` launcher activity.** #171's scope explicitly includes
  *deleting* the redundant `src/debug/BackupDebugActivity`; adding a second one creates cleanup work
  and re-commits the exact anti-pattern the amended Gate 5 was written to stop. The designed viewer
  is verified in WI-6a/WI-6b by connected Compose tests against the extracted `…Content` composable (the
  house pattern), which is a test harness, not a shipped surface.
- **WI-1 … WI-7 are mergeable now** and take the row to `DONE`. **WI-8 and WI-9 are blocked on #171.**
- **The row may NOT be flipped to `VERIFIED` before #171 lands** and WI-8/WI-9 complete, per rule 47
  Gate 5 "Production reachability". The Gate-5b evidence file must name the user-visible path
  (`Library → Settings → Support → Diagnostics → share`), which is unwritable until #171 exists.

---

### 3.1 Dispatch split — what is shippable NOW vs blocked (read this before dispatching)

| WI | Tier | Dispatchable now? | Notes |
|---|---|---|---|
| **WI-1** engine core + logcat source | foundational | ✅ **YES — dispatch FIRST, alone** | **Feasibility gate.** Nothing downstream should start until it passes; if it fails, §2's go/no-go decides whether WI-2… are worth building |
| **WI-2** redactor | foundational | ✅ YES — parallel with WI-1 | `depends: []`, disjoint write-set; the security gate |
| **WI-3** `VLog` + ring + composite | foundational | ✅ after WI-1 | migrates the 6 `Log.*` sites |
| **WI-4** store | foundational | ✅ after WI-1/2/3 | |
| **WI-5** view model | foundational | ✅ after WI-4 | |
| **WI-6a** row / chips / footer | behavioral | ✅ after WI-5 | connected Compose tests |
| **WI-6b** screen shell + states | behavioral | ✅ after WI-6a | adds the orphan-surface allowlist entry |
| **WI-7** export + provider + share | behavioral | ✅ after WI-4/WI-6b | |
| **WI-8** Settings entry row | behavioral | ❌ **BLOCKED on #171** | `dispatchable: false` — write-set cannot be completed until #171's hub file exists; runs INLINE, never as a lane |
| **WI-9** acceptance pass | acceptance | ❌ **BLOCKED on #171** | orchestrator/verifier work, `writes: []` |

**WI-1 … WI-7 take the row to `DONE`.** They are all dispatchable today and deliver the whole
engine, the designed viewer, and the redacted export.

**WI-8 + WI-9 cannot land until #171 does**, and #171 is `TODO`, unmirrored, and itself blocked on
design #2018 — so **`VERIFIED` is not reachable on any timeline this plan controls**. Starting
WI-1…WI-7 now is still correct (the work is real and independent), but it must be started with eyes
open: the row parks at `DONE` indefinitely.

**Two rule-51 `needs-design` issues are FILED and OPEN. Both block nothing.** Verified to exist —
not asserted (see the Revision history's correction note):

| Issue | Surface | Plan context |
|---|---|---|
| **GH #2021** | Diagnostics **WARN level treatment** (chip + row token) | §6.3 — the interim confines WARN to the `All` chip with the `debug` treatment until this lands |
| **GH #2022** | Diagnostics **capture-unavailable empty state** | §6.5 — the designed empty state ships verbatim meanwhile; availability shows only in the export header |

If either design lands before WI-6a/WI-6b are implemented, that WI implements it instead of the
interim.

## 4. Surface area

New package: `android/app/src/main/kotlin/com/vreader/app/diagnostics/`.

### 4.1 Engine (new files)

```kotlin
// DiagnosticsLevel.kt
enum class DiagnosticsLevel(val priorityChar: Char, val exportTag: String) {
    VERBOSE('V', "VERBOSE"), DEBUG('D', "DEBUG"), INFO('I', "INFO"),
    WARN('W', "WARN"), ERROR('E', "ERROR"), ASSERT('F', "ASSERT");
    companion object { fun fromPriorityChar(c: Char): DiagnosticsLevel? }
}

// DiagnosticsLogEntry.kt
data class DiagnosticsLogEntry(
    val timeMillis: Long,      // epoch millis, UTC-parsed
    val level: DiagnosticsLevel,
    val category: String,      // logcat tag, trimmed; "" when absent
    val message: String,       // may be multi-line (stack traces); marker already STRIPPED
    // Gate-2 High: dedupe needs a representable identity. VLog stamps a monotonic id and emits
    // it as a compact leading marker "«v<N>»" in the android.util.Log message; the parser strips
    // the marker and lifts it into this field. Null = not a VLog-originated entry (framework,
    // library, or a truncated line whose marker was lost).
    val sequenceId: Long? = null,
)

// DiagnosticsLogSource.kt — the testable seam (iOS DiagnosticsLogSource analog).
// Returns SourceResult (defined below), NOT a bare list: availability must be an explicit
// signal so the composite can distinguish "this source is dead" from "this source is empty".
interface DiagnosticsLogSource {
    /** Up to [limit] entries, oldest→newest, optionally bounded to [sinceMillis].
     *  NEVER throws — a source failure is reported as SourceResult.Unavailable. */
    suspend fun recentEntries(sinceMillis: Long? = null, limit: Int): SourceResult
}

// LogcatLineParser.kt — PURE, the JVM-testable half of the logcat source
object LogcatLineParser {
    /** Parses `-v uid -v threadtime -v year -v UTC` output. Skips `--------- beginning of X`
     *  dividers; appends continuation lines (stack traces) to the previous entry's message;
     *  drops rows whose uid != [ownUid]. */
    fun parse(lines: Sequence<String>, ownUid: Int): List<DiagnosticsLogEntry>
}

// LogcatDiagnosticsSource.kt — the OS boundary (not JVM-unit-tested; connected-tested)
class LogcatDiagnosticsSource(
    private val ownUid: Int = android.os.Process.myUid(),
    private val maxLines: Int = 5_000,
    private val maxBytes: Int = 2 * 1024 * 1024,
    // Gate-2 M4: the timeout path must CLOSE streams, destroy(), then destroyForcibly() if still
    // alive, and ALWAYS waitFor() to reap — a bare destroy() can leave a logcat child or its
    // drain thread alive.
    private val processTimeoutMs: Long = 5_000,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val exec: (List<String>) -> Process = { ProcessBuilder(it).redirectErrorStream(true).start() },
) : DiagnosticsLogSource

// RingBufferDiagnosticsSource.kt — in-process floor; also the VLog sink
class RingBufferDiagnosticsSource(private val capacity: Int = 500) : DiagnosticsLogSource {
    fun record(level: DiagnosticsLevel, category: String, message: String, at: Long)
}

// CompositeDiagnosticsSource.kt — REPLACES the v1 "primary-else-floor" design (Gate-2 M1).
// v1's contract ("primary empty -> use fallback") had two real defects: a legitimately empty
// logcat flip-flopped the source on every load, and a PARTIALLY populated logcat hid ring
// entries entirely. Availability is now an EXPLICIT signal, not inferred from emptiness.
sealed interface SourceResult {
    data class Available(val entries: List<DiagnosticsLogEntry>) : SourceResult  // incl. empty
    data class Unavailable(val reason: String) : SourceResult                    // exec failed/denied
}

// Merges BOTH sources whenever the primary is Available, so ring entries are never hidden by a
// partially-populated logcat. Dedupe matches on sequenceId (identity), never on fuzzy
// (time,tag,message) equality.
//
// Gate-2 High — the marker's failure modes are SPECIFIED, not assumed:
//  * marker is a LEADING token, so logd's 4068-byte payload truncation (which cuts the TAIL)
//    cannot destroy it;
//  * an entry whose sequenceId is null on the logcat side (framework/library line, or a marker
//    that failed to parse) is treated as DISTINCT and kept — dedupe never drops an entry it
//    cannot positively identify (fail-open on retention, not on suppression);
//  * a ring entry whose logcat twin was dropped under buffer pressure still surfaces from the
//    ring, which is the whole point of merging;
//  * the parser STRIPS the marker before the entry reaches the store, so it never appears in the
//    viewer or the export payload (asserted in WI-1 and WI-3).
class CompositeDiagnosticsSource(
    private val primary: DiagnosticsLogSource,   // logcat
    private val secondary: DiagnosticsLogSource, // ring buffer
) : DiagnosticsLogSource

// VLog.kt — the facade (forwards to android.util.Log AND the ring buffer)
// Gate-2 High: the enum MUST match the design's category vocabulary
// (DIAG_CATEGORIES, vreader-diagnostics.jsx:70) — v1 dropped Persistence (the design's
// most-exercised category) and DebugBridge, and invented Search/Data/Share.
enum class DiagnosticsCategory(val tag: String) {
    LIBRARY("Library"), PERSISTENCE("Persistence"), READER("Reader"),
    AI("AI"), SYNC("Sync"), DEBUG_BRIDGE("DebugBridge")
}
// Android-only concerns map ONTO the designed set rather than extending it:
//   search indexing -> LIBRARY   Room/DAO -> PERSISTENCE   share/export -> LIBRARY

// DiagnosticsCategoryBounding.kt — Gate-2 High: the chip row must stay BOUNDED.
// Merged output carries RAW LOGCAT TAGS from the framework and every library (Readium, chromium,
// SQLiteLog, OkHttp, ART, ...). The design shows 7 chips in a scrollable row; unbounded production
// tags would render dozens. Rule:
//   1. a tag matching a DiagnosticsCategory.tag keeps it;
//   2. a known-library tag maps to the nearest designed category via an explicit table;
//   3. everything else collapses into ONE bucket rendered with the design's existing chip;
//   4. the chip row is HARD-CAPPED at the designed 7 (+ "All"), ranked by entry count.
// Filtering by the collapsed bucket still shows those entries; only the CHIP set is capped.
object DiagnosticsCategoryBounding { fun chips(entries: List<DiagnosticsLogEntry>): List<String> }
object VLog {
    fun install(sink: RingBufferDiagnosticsSource, clock: () -> Long = System::currentTimeMillis)
    fun w(cat: DiagnosticsCategory, message: String, t: Throwable? = null)
    fun i(cat: DiagnosticsCategory, message: String)
    fun d(cat: DiagnosticsCategory, message: String)
    fun e(cat: DiagnosticsCategory, message: String, t: Throwable? = null)
}

// DiagnosticsRedactor.kt — PURE. The ONLY export-leak barrier on Android.
object DiagnosticsRedactor {
    const val PLACEHOLDER = "‹redacted›"
    const val PATH_PLACEHOLDER = "‹path›"
    fun redact(message: String): String   // idempotent
}

// DiagnosticsLogStore.kt — UI-facing store (iOS DiagnosticsLogStore analog)
class DiagnosticsLogStore(
    private val source: DiagnosticsLogSource,
    private val maxEntries: Int = 2_000,
) {
    suspend fun load(sinceMillis: Long? = null, limit: Int? = null): List<DiagnosticsLogEntry>
    /** Distinct non-empty categories, sorted — the RAW set present in the entries (iOS
     *  `var categories`). This is NOT what the chip row renders: the chip row is
     *  `DiagnosticsCategoryBounding.chips(...)`, which maps/collapses/caps this set to the
     *  designed 7. Keeping them separate is deliberate — filtering must still reach an entry
     *  whose raw category collapsed into the bucket. (Gate-2 R3 High: v3 described this as
     *  "drives the chip row", which contradicted the bounding rule and would have let raw
     *  framework tags render dozens of chips.) */
    fun categories(entries: List<DiagnosticsLogEntry>): List<String>
    /** True when the last load's primary source reported Unavailable — feeds the export
     *  header's `capture source:` line (NOT the viewer copy; see §6.5). */
    val lastLoadDegraded: Boolean
    fun exportText(entries: List<DiagnosticsLogEntry>, generatedAt: Long): String
    companion object { const val CAPTURE_SCOPE_LABEL = "recent activity" }
}

// DiagnosticsExportWriter.kt — atomic write into filesDir/diagnostics/.
// Gate-2 M2: the filename is DERIVED INTERNALLY from the injected clock, never caller-supplied,
// so no traversal input exists to sanitize. The writer additionally asserts the resolved file is
// a canonical child of `dir` before writing (defence in depth against a future refactor).
class DiagnosticsExportWriter(
    private val dir: File,
    private val clock: () -> Long,
    private val ioDispatcher: CoroutineDispatcher,
) {
    /** Writes to "vreader-log-YYYY-MM-DD.txt" derived from `clock`; temp -> atomic rename;
     *  prunes prior exports. Returns the promoted file. */
    suspend fun write(text: String): File
}

// DiagnosticsFileProvider.kt — a SEPARATE FileProvider (see §6.4), no DISPLAY_NAME override
class DiagnosticsFileProvider : FileProvider()

// DiagnosticsShareIntent.kt — own share builder + own path guard.
// Gate-2 M5: the "no ActivityNotFoundException escapes" guarantee belongs to the LAUNCHER, not
// to a function that merely returns an Intent — mirrors BookShareIntent.shareBook's shape.
fun shareDiagnosticsIntent(context: Context, file: File): Intent?  // null if outside diagnostics/
fun shareDiagnostics(context: Context, file: File)                 // catches ActivityNotFoundException
```

### 4.2 UI (new files, `com/vreader/app/diagnostics/ui/`)

Built **strictly** from `vreader-diagnostics.jsx` / `diagnostics-artboards.jsx`:

| File | Design component |
|---|---|
| `DiagnosticsScreen.kt` | `DiagLogViewer` — the whole pushed screen; splits into `DiagnosticsScreen` (host) + `DiagnosticsScreenContent` (testable), per the `ReaderSettingsSheet`/`…Content` and `BookDetailsSheet`/`…Content` house convention |
| `DiagnosticsNavShell.kt` | **`DiagNavSheet`** (`vreader-diagnostics.jsx:137-183`) — grabber, leading back control, centered Source-Serif title, trailing action slot. **Gate-2 High: v1/v2 named no file for the nav shell at all**, while WI-6 simultaneously asserted "HIDES the share affordance" — asserting a component the plan never specified. See §6.5 |
| `DiagnosticsShareButton.kt` | **`DiagShareButton`** (`:186-197`) — the 28×28 round trailing share affordance |
| `DiagnosticsIcons.kt` | **`DiagPulseIcon`** (`:31-36`, path `M3 12h4l2.5-6 5 12 2.5-6h4`) — a custom glyph, **not** in material-icons-extended, required by the empty-state tile and the WI-8 Settings row. Ships as an `ImageVector`; no `res/drawable` needed |
| `DiagnosticsFilterBar.kt` | `DiagFilterBar` + `DiagChip` — level row (All/Errors/Debug/Info with counts, Errors tints to the error color when active) + horizontally-scrolling category row |
| `DiagnosticsLogRow.kt` | `DiagLogRow` + `DiagDayHeader` — mono timestamp · uppercase colored level · mono category pill; monospace message clamped to 3 lines; tap → expanded + "Copy entry" |
| `DiagnosticsLevelStyle.kt` | `diagLevelColor` — error `#b13e36`/`#e0826f`, info `#3a6f9c`/`#7fb2d9`, debug `theme.sub` (light/dark) |
| `DiagnosticsStates.kt` | `DiagLoading` (spinner + `logcat · com.vreader.app`), `DiagEmpty` (plain + filtered-with-"Clear filters") |
| `DiagnosticsFooter.kt` | `DiagFooter` — mono scope line + green-dot "Capturing" |
| `DiagnosticsViewModel.kt` / `DiagnosticsUiState.kt` | `StatsViewModel` pattern: private `MutableStateFlow` inputs → `map`/`flatMapLatest` → `.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DiagnosticsUiState())` |

### 4.3 Modified existing files

| File | Change |
|---|---|
| `android/app/src/main/res/xml/diagnostics_paths.xml` | **NEW file** — `<files-path name="diagnostics" path="diagnostics/"/>`. `file_paths.xml` is **NOT touched** (see §6.4). |
| `android/app/src/main/AndroidManifest.xml` | **Add** a second `<provider>`: `DiagnosticsFileProvider`, authority `${applicationId}.diagnosticsprovider`, `exported="false"`, `grantUriPermissions="true"`, `@xml/diagnostics_paths` |
| `android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt` | `AppContainer`: `by lazy` `diagnosticsRing`, `diagnosticsSource`, `diagnosticsStore`, `diagnosticsExportWriter`; `diagnosticsViewModel()` factory; `VLog.install(...)` in `VReaderApp.onCreate()` |
| `PdfDocument.kt:101`, `ReaderActivity.kt:756`, `FoliateBridge.kt:93`, `BookShareIntent.kt:48/:76`, `SearchIndexCoordinator.kt:157` | migrate `Log.w(...)` → `VLog.w(DiagnosticsCategory.X, ...)` (6 sites) |
| `android/version.properties` | rule-40 bump — **allocated by the ORCHESTRATOR at each merge slot** (rule 40 "Batch mode" + rule 55 version-at-slot), never by a lane. Lanes carry only `bump_tier` in the HANDOFF |
| `docs/architecture.md` | rule-24: new Android diagnostics subsystem + the new `DiagnosticsFileProvider` |
| `README.md` | rule-24: Diagnostics is a **user-visible** feature, so the Features section gets a bullet. Landed with WI-8 (when it becomes reachable), NOT with WI-1 — advertising a screen no user can open is the #114/#120 mistake in documentation form. Recorded here so the rule-24 check is answered rather than skipped. |

### 4.4 Files explicitly OUT of scope

- **Any Settings screen / hub / gear affordance / navigation host** — #171 owns it (§3).
- **`android/app/src/debug/**`** — no new debug launcher (§3).
- **The book share/provider LOGIC** — `BookFileProvider.kt`, `file_paths.xml`, and
  `BookShareIntent.kt`'s intent-building and `isInsideBooksDir` guard are untouched (§6.4):
  diagnostics gets its own provider, paths xml, intent builder and path guard.
  **Precision (Gate-2 M)**: WI-3 *does* edit two lines **in** `BookShareIntent.kt` — its two `Log.w`
  call sites (`:48`, `:76`) migrate to `VLog` like the other four. "Untouched" refers to the share
  logic, not to the file being byte-frozen; the file appears in WI-3's write-set for that reason.
- **`:identity` module** — diagnostics is device-local, not a cross-platform contract; nothing in
  `contracts/` changes, no backup section is added.
- **iOS (`vreader/`, `vreaderTests/`, `project.yml`, `*.xcodeproj`)** — rule-48 cross-platform write isolation.
- **Crash/ANR capture, `Thread.setDefaultUncaughtExceptionHandler`, upload-to-server, log-level
  settings UI, a Warn chip** — all undesigned and/or unscoped. Named as follow-ups in §8.
- **`docs/features.md`, `docs/parity/*`, `.claude/*`, `scripts/*`** — another writer owns them this
  batch. **Two narrow carve-outs** (Gate-2): `scripts/.orphan-surfaces-allow` (one annotated entry,
  added by WI-6b and removed by WI-8 — see WI-6b's notes) and one new check under
  `scripts/__tests__/` for the `android.util.Log` containment gate in WI-3. Both are additive and
  touch no existing script.
- **`android/version.properties`** — NOT written by any WI. Under rule 40 "Batch mode" + rule 55 the
  **orchestrator** allocates the version at the merge slot; lanes carry only a `bump_tier` in the
  HANDOFF. A lane that bumped it would trip both `check-write-set.sh` and the merge-gate audit hook
  (the file classifies as a code path).

---

## 5. Prior art, project precedent, rejected alternatives

### Ported from iOS #96 (298 lines read in full)

| iOS | Android | Note |
|---|---|---|
| `DiagnosticsLogSource` protocol | `DiagnosticsLogSource` interface | same seam, but Android **deliberately diverges**: iOS collapses a throwing source to "no entries"; Android returns an explicit `SourceResult.Available`/`Unavailable` because it has *two* sources and must distinguish "log is empty" from "capture is dead" (Gate-2 M1) |
| `OSLogDiagnosticsSource` (`OSLogStore(scope:.currentProcessIdentifier)`) | `LogcatDiagnosticsSource` (`logcat -d` uid-filtered) | **scope differs — see below** |
| `DiagnosticsLogStore` (`@MainActor @Observable`) | `DiagnosticsLogStore` (plain class) + `DiagnosticsViewModel` (`StateFlow`) | Compose/Kotlin analog per rule 50 §12 |
| `DiagnosticsRedactor` (8 regex rules) | `DiagnosticsRedactor` (all 8 + 4 Android rules) | §6 |
| `DiagnosticsLogViewModel` (level/category filters, counts, day sections, footer scope, export filename) | `DiagnosticsViewModel` | 1:1 semantics, incl. **Errors chip = a level SET, not one level** |
| `DiagnosticsLogStore.captureScopeLabel = "this session"` | `CAPTURE_SCOPE_LABEL = "recent activity"` | see below |

**Capture-scope divergence (deliberate, documented).** iOS is `.currentProcessIdentifier` → strictly
the current launch, so #96 set the label to `"this session"`, *deliberately superseding* the design
mock's illustrative `"last 24 h"` (`DiagnosticsLogStore.swift:24-30`). Android's logd ring retains
entries **by uid across process launches** until the 2 MiB buffer rotates — so Android can show
*pre-crash* entries from a previous launch, which iOS cannot. Neither `"this session"` (too narrow)
nor `"last 24 h"` (a fixed window we don't control) is accurate; the label is **`"recent activity"`**,
single-sourced in `CAPTURE_SCOPE_LABEL` and used by both the footer and the export header exactly as
iOS single-sources its own. This is the same class of correction #96 already made, applied to a
different platform truth.

### Project precedent reused

- **`AppContainer` manual DI** (`VReaderApp.kt:51`) — no Hilt/Koin/Dagger anywhere; singletons are
  `by lazy` properties, ViewModels are `viewModelFactory { initializer { … } }` (`MainActivity.kt:46-48`).
- **`StatsViewModel`** (`stats/StatsViewModel.kt:21-25`) — the canonical
  `MutableStateFlow` → `stateIn(viewModelScope, WhileSubscribed(5_000), default)` shape.
- **`ReaderSettingsSheet` / `ReaderSettingsSheetContent`** split (`ReaderSettingsSheet.kt:53,76`) — the
  host/testable-content convention connected tests call directly.
- **`BookImporter.importStream`** (`data/BookImporter.kt:54-95`) — `createTempFile(…, ".part", dir)` (`:70`) then
  atomic promote; copied for the export writer.
- **`BookShareIntent`** (`reader/share/BookShareIntent.kt:34-59`) — `ACTION_SEND` + `EXTRA_STREAM` +
  `FLAG_GRANT_READ_URI_PERMISSION` + matching `ClipData` + `createChooser`; copied in shape, not widened.
- **Injected `CoroutineDispatcher` with a default** — the house convention (23 files under
  `app/src/main`); no qualifiers,
  no hardcoded `Dispatchers.IO`.
- **Reusing an iOS design bundle in Compose is rule-51-compliant** — established at #106 and used by
  every Android parity feature since.

### Rejected alternatives

| Rejected | Why |
|---|---|
| **In-process ring buffer as the ONLY source** | With 6 `Log.w` sites it captures ~nothing that diagnoses a real bug. The high-value content (Readium, WebView console, Room, `HttpURLConnection`/WebDAV, ART crash traces) comes from libraries we don't own and never routes through our facade. |
| **logcat as the ONLY source** | One platform-policy change (or one OEM's SELinux) empties the feature with no floor. §2's caveat is unresolved until WI-1's connected test runs on-device. |
| **Merge + dedupe on `(time, level, tag, message)`** (fuzzy identity) | Fragile: logd rewrites timestamps and truncates at 4068 B, so the "same" event differs between sources; and two genuinely distinct entries with identical text/timestamp would be wrongly collapsed. **Superseded by identity dedupe on a VLog sequence id**, which is what the plan now specifies. |
| **`FallbackDiagnosticsSource` — "primary, else floor"** (the v1 design, rejected at Gate-2 M1) | Inferring availability from emptiness is wrong twice over: a legitimately empty logcat flip-flops the source on every load, and a *partially* populated logcat hides the ring's entries entirely. Replaced by an explicit `SourceResult.Available`/`Unavailable` signal plus `CompositeDiagnosticsSource`, which merges. |
| **`--pid=<myPid>`** | Discards prior-launch entries — exactly the pre-crash trail that makes Android's scope better than iOS's. uid filtering (logd's own + our parser's `-v uid` check) is the correct boundary. |
| **Request `READ_LOGS`** | `signature\|privileged`; not grantable. Would also make the export a cross-app privacy hazard. |
| **A `WorkManager`/foreground service continuously draining logcat to disk** | Battery + storage cost, a persistent notification on API 26+, and a much larger PII footprint at rest — for a screen opened a handful of times per install. Pull-on-open is right. |
| **Pinned "Export log…" footer CTA** (design **X2**) | Explicitly rejected *in the design*: "spends permanent vertical space on a rare action and crowds the status footer." |
| **Error-count badge on the Settings row** (design **X3**) | Explicitly rejected *in the design*: "makes Settings feel alarming for errors the user can't act on." |
| **Adding a "Warn" chip** | Undesigned → rule 51. See §6.3 for the mapping actually used. |
| **A `src/debug` launcher to eyeball the viewer** | §3 — recreates the anti-pattern #171 exists to delete. |

---

## 6. Design decisions requiring explicit adjudication

### 6.1 Threat model — the redactor is the ONLY barrier

On iOS the **first** barrier is OSLog `privacy:` annotations: `.private` interpolations read back as
`<private>` and are unrecoverable, so `DiagnosticsRedactor` is defense-in-depth. **Android logcat is
plaintext with no privacy barrier at all.** Every byte an app logs is in the buffer verbatim. The
redactor is therefore *load-bearing*, not defensive, and its test suite is the feature's security gate.

#### Redaction applies at EVERY egress point, not just export (Gate-2 CRITICAL)

There are **two** ways a log entry leaves the device, and plan v1/v2 guarded only one:

1. **Share/export** — the whole filtered list → `exportText()` → redacted. ✅
2. **"Copy entry"** — a single row's full message → the system clipboard → **was UNREDACTED**. ❌

The second is arguably the *more* likely leak: a user who long-presses a red error row and pastes it
into a GitHub issue is doing exactly what a bug-report workflow invites, and would paste
`Authorization: Bearer sk-…` verbatim into a public tracker.

**iOS already got this right and we missed it**: `DiagnosticsLogView.swift:173` reads
`UIPasteboard.general.string = DiagnosticsRedactor.redact(entry.message)`. The parity claim in §5 was
made after reading `vreader/Services/Diagnostics/` (298 lines) but **not**
`vreader/Views/Settings/Diagnostics/`, where the clipboard call site lives — a reading gap, now closed.

**Rule for this feature**: `DiagnosticsRedactor.redact()` is applied at **every** egress —
`exportText()`, the clipboard, and any future share/upload path. The expanded row may *display*
the full message on-screen (on-device display is not egress); the moment it crosses to the clipboard
it is redacted. Asserted in WI-6a, not left to reviewer vigilance.

Known Android leak shapes, from the actual credential paths in this codebase:

| Shape | Real source | Rule |
|---|---|---|
| `Authorization: Bearer <key>` | `OpenAiCompatibleProvider.kt:35` | ported iOS rule 1 |
| `Authorization: Basic <b64>` | `WebDavClient.kt:104`, `:144`, **`:195`**, `OpdsClient.kt:61` | ported iOS rule 1 |
| `x-api-key: <key>` | `AnthropicProvider.kt:32` | ported iOS rules 2/3 (`keys` alternation already includes `x-api-key`) |
| `sk-…` / `sk-proj-…` | OpenAI-compatible providers | ported iOS rule 4 |
| JWT `eyJ….….…` | any OIDC-ish provider | ported iOS rule 5 |
| `https://user:pass@host/dav` | WebDAV / OPDS URLs | ported iOS rule 6 |
| `file:///…` | ported | ported iOS rule 7 |
| `/data/user/<n>/com.vreader.app/…`, `/data/data/…` | app-private paths (`<n>` is any user id — work profiles / secondary users are NOT always `0`) | **new (Android)** |
| `/storage/emulated/0/…`, `/sdcard/…` | shared storage, may embed a real user name | **new (Android)** |
| `content://…/document/…` | SAF import URIs (embed filenames) | **new (Android)** — keep authority, redact the path |
| base64 GCM token from `SecretCipher` | `encryptedPassword` / `encryptedApiKey` fields on the stored entities | **NOT covered by the ported iOS rules — this was a false claim in plan v1.** The iOS `keys` alternation is `(?:x-api-key\|api[_-]?key\|access[_-]?token\|refresh[_-]?token\|client[_-]?secret\|token\|password\|secret)`, which does **not** match the camelCase `encryptedApiKey` / `encryptedPassword` this codebase actually uses (`api[_-]?key` requires a separator or word start; `encryptedApiKey` embeds it mid-token). A **new** rule is required: `(?i)\b\w*(?:encrypted)?(?:apikey\|api_key\|password\|secret\|token)\w*\s*[:=]` with the value consumed — plus a serialized-entity-dump vector, since a whole entity `toString()` is the realistic leak path. **No** blanket base64 rule (iOS precedent: over-redacts hashes/ids) |

**Accepted limitation (parity with iOS, flagged for the auditor):** book **titles and filenames** are
not redacted. An exported log reveals what the user reads. iOS #96 made the same call, and redacting
titles would gut the log's diagnostic value (most import/reader failures name the book). Documented in
the row's Known limitations rather than silently inherited.

**OVER-redaction hazard the path rule creates (Gate-2 Medium).** The new
`/data/user/<n>/com.vreader.app/…` rule would swallow the **fingerprint key**, because book artifacts
live at `filesDir/books/<sanitized fingerprintKey>` (`BookImporter.fileNameForKey`) — and that key is
the single handle every import/reader bug is filed against. It would also directly contradict the
limitation just above ("filenames are not redacted"). This is *not* iOS parity: iOS's container-path
rule (`DiagnosticsRedactor.swift:79`) redacts a path whose tail carries no comparable identifier.
**Rule**: redact the app-private path **prefix** only, preserving the trailing segment under
`books/` — `‹path›/epub_a1b2…_4`. WI-2 asserts the fingerprint key SURVIVES redaction.

**Under-redaction the keyed rules still miss (Gate-2 Medium).** The dominant Kotlin logging shape is
string-template interpolation of a *bare* value — `VLog.w(cat, "decrypt failed for $encrypted")` —
which has **no key name** and therefore matches none of the keyed rules, while the plan deliberately
declines a blanket base64 rule. So the `SecretCipher` blob is **not** fully covered, and claiming
otherwise would repeat the v1 error. **A framing-based rule is NOT available** (Gate-2 R3 Medium — v3 proposed one and was wrong):
`KeystoreSecretCipher.encrypt` returns `Base64.getEncoder().encodeToString(iv + ct)`
(`SecretCipher.kt:35`, documented at `:25` as *"base64( iv ‖ ciphertext )"*) — there is **no prefix,
no length field, no magic**. The token is an opaque base64 blob, structurally indistinguishable from
any hash, id, or cover thumbnail the log legitimately contains, so the only rule that would catch it
is the blanket base64 rule this plan deliberately rejects for over-redaction.

Therefore this is an **explicitly accepted limitation**, not a mitigated one: bare-value
interpolation of a secret is a logging-discipline problem the redactor *cannot* solve. The real
control is the `VLog` seam — never interpolate a credential field — which at least makes the rule
reviewable in one place and greppable in code review. Recorded in §11.

### 6.2 The export is a *file*, not clipboard text

Design **X1** is canonical: nav-trailing share icon → system share sheet with a `.txt` payload;
`DiagShareMock` specifies the payload header — filename `vreader-log-2026-06-10.txt`, subtitle
`Plain text · 312 KB · last 24 h`. Android maps this to `ACTION_SEND` + `type="text/plain"` +
`EXTRA_STREAM` (FileProvider URI), which is also what the two existing share flows do.

### 6.3 Android's `WARN` has no designed home — mapping, not invention

> **`ASSERT` and `VERBOSE` closed here too (added 2026-08-05 from WI-6a's HANDOFF).** This section
> adjudicated `WARN` and was silent on the other two of Android's six priorities. WI-6a's
> implementation maps **`ASSERT` → the error treatment** and **`VERBOSE` → the debug treatment**,
> and that is now the plan's ruling rather than an implementer's choice. It is *derivable, not
> invented*: WI-5 already ships those exact groupings as the chips' **level sets** (`Errors =
> {ERROR, ASSERT}`, `Debug = {VERBOSE, DEBUG}`), so a row whose treatment disagreed with the chip
> that selects it would be self-contradictory — an `ASSERT` entry surfacing under **Errors** while
> rendering in the debug colour. No new visual token is introduced (unlike the withdrawn v1 WARN
> proposal below, which is exactly why that one was rejected). Recorded in `DiagnosticsLevelStyle.kt`'s
> header.

The design provides **four level chips** (`All`, `Errors`, `Debug`, `Info`) and **three** row color
treatments (error / info / debug). Android has six priorities (`V D I W E F`), and **all 6 existing
production log sites are `Log.w`** — so a naive `Errors = {E, F}` mapping would leave vreader's own
entries invisible under every non-`All` chip, which is precisely backwards for a bug report.

**The v1 proposal, now WITHDRAWN** (kept only so the reasoning trail is legible): map
`Errors = {W, E, F}` · `Info = {I}` · `Debug = {V, D}` and render the literal `WARN` token in the
error color, on the argument that the design's level token is a data-driven string
(`DiagLogRow` renders `{e.level}` uppercase) and that iOS already treats the Errors chip as a *set*
(`DiagnosticsLogViewModel.swift:9-11`: *"the Errors chip can include `.fault` — the store's single
`level:` predicate can't express a set"*). **Both round-1 auditors rejected it, correctly.** The
set-membership precedent holds; the *new visual token* does not, and the count inflation below is
disqualifying on its own. See the adjudication that follows for the decision actually adopted.

**GATE-2 ADJUDICATION (both round-1 auditors pushed back; the author's v1 framing was too
comfortable).** The mechanism claim is verified — `DiagLogRow` does render `{e.level}` uppercase in a
functional color (`vreader-diagnostics.jsx:272`) — but the design's *data* vocabulary is exactly
three tokens, `error | info | debug` (`:41-53`). A fourth token is a new visual state, and rule 51 is
explicit that *"looks similar to existing X does NOT count."* Two further facts sharpen it:

- **The "Errors" chip would count warnings.** Its designed count (`DIAG_COUNTS.error`) becomes
  `{W,E,F}`, so on *this* codebase — where all 6 production sites are `Log.w` — **every** production
  entry renders as an error. A screen that shows a user 6 red rows for routine handled conditions is
  actively misleading, which is a worse outcome than the vocabulary question.
- The three candidate resolutions are: (a) render the truthful `WARN` token in the error color — a
  4th token, undesigned; (b) render `ERROR` for warn-level entries — stays in vocabulary but *lies*
  about severity; (c) file for a designed Warn treatment.

**Decision: (c) — FILED as GH #2021** (*"Design needed: Diagnostics WARN level treatment (chip + row
token) for feature #164"*, labels `enhancement` + `needs-design`, OPEN). Option (b) is rejected
outright: a diagnostics tool that misreports severity is worse than one with a missing chip.
An implementer picking up WI-5/WI-6a should read **#2021** before touching level rendering.

**Interim, pending that design** — ship `Errors = {E, F}`, `Info = {I}`, `Debug = {V, D}` exactly as
designed, and let warn-level entries appear **only under the `All` chip**, rendered with the
`debug` treatment. This invents no token and no color, keeps the Errors count honest, and leaves our
6 breadcrumbs reachable (under `All`). It is strictly worse than a designed Warn chip, which is why
the issue is filed rather than deferred.

**Does the interim itself invent a token?** (Gate-2 R3 Medium — v3's breezy "this blocks nothing"
was wrong to leave unexamined.) `DiagLogRow` renders `{e.level}` uppercase, so a warn-level entry
under the `All` chip WILL print the literal string `WARN` in the debug color — a fourth token,
undesigned, and on today's codebase **every** production entry is `Log.w`, so this is the common
case, not an edge case. Two honest options:

- **(i) Render warn-level rows with the `DEBUG` token** (not `WARN`) in the debug treatment. Invents
  nothing — stays exactly inside the design's three-token vocabulary — at the cost of under-stating
  severity for entries that are, on this codebase, genuinely just handled conditions. The level is
  still recoverable from the exported text, which carries the true `[WARN]` tag.
- **(ii) Block WI-6a's level rendering on #2021.** Strictly rule-51-correct; stalls the viewer.

**Recommendation: (i)**, and it is the plan's default — it is the only option that ships a designed
screen without inventing a token, and unlike the rejected option (b) it errs toward *under*-stating
severity rather than crying error on everything. **#2021 remains the real fix.** If the user wants
strict sequencing instead, (ii) is the switch — flagged here so it is the user's call, not the
implementer's.

### 6.4 A SEPARATE FileProvider — not a new root on `file_paths.xml`

The obvious move (add `<files-path name="diagnostics" path="diagnostics/"/>` to the existing
`file_paths.xml`) is **wrong**, and the reason is not cosmetic. Verified in source:

- `AndroidManifest.xml:48-56` declares exactly one provider, `.reader.share.BookFileProvider`,
  authority `${applicationId}.fileprovider`, resource `@xml/file_paths`.
- `file_paths.xml` exposes only `<files-path name="books" path="books/"/>` and its own comment states
  the security property this buys: *"Nothing else under filesDir is shareable … **Do NOT widen this
  to `<files-path path="."/>`**."* Adding a `diagnostics/` root does not widen scope to the *same
  degree* as `path="."` (which would expose the Room DB, DataStore prefs and books) — that
  equivalence, asserted in an earlier draft, was **overstated and is withdrawn**. It does, however,
  make the comment's blanket claim false and grow the book provider's blast radius for no benefit.
- `BookFileProvider.displayNameFor()` (`BookFileProvider.kt:69-75`) resolves the label by the
  **URI's trailing filename segment** matched against a **global** `registrations` map —
  `registrations.values.firstOrNull { it.fileName == fileName }` — which is *not* scoped to `books/`.
  In practice a diagnostics file would fall through to `super.query()`, because registrations are
  populated only from the book-share path and `books/` names are fingerprint-derived
  (`epub_<sha>_<n>`), structurally disjoint from `vreader-log-YYYY-MM-DD.txt`; and the failure mode
  would be a cosmetic DISPLAY_NAME mislabel, **not** a content leak. So this is a *latent coupling*,
  not a live bug — the earlier draft's "working by luck" framing was too strong and is also withdrawn.

The decision below is therefore justified on **blast-radius isolation and removing a latent coupling
to a global, unscoped display-name registry** — a cheap, structural separation — rather than on an
imminent vulnerability.

**Decision**: declare a second provider, `DiagnosticsFileProvider` (a plain `FileProvider()` subclass,
no query override), authority `${applicationId}.diagnosticsprovider`, `exported=false`,
`grantUriPermissions=true`, backed by a **new** `res/xml/diagnostics_paths.xml` holding only the
`diagnostics/` root. `BookFileProvider`, `file_paths.xml`, and `BookShareIntent` are then genuinely
untouched, each provider grants exactly one directory, and neither feature can widen the other's
scope. Cost: one `<provider>` element and one 3-line xml file.

### 6.5 The Android container for an iOS-sheet design, and the degraded-source state

Two gaps that would otherwise force an implementer to invent UI (rule 51).

**(a) The container.** The design's `DiagNavSheet` is an iOS bottom sheet: grabber, `‹ Settings`
back, centered serif title, trailing share. Reusing an iOS bundle in Compose is established
practice here (#106 onward), but the plan must say *what shell* to build or WI-6b becomes an
invention. Decision: build the **same sheet vocabulary the app already ships** for its designed
sheets (the `ReaderSettingsSheet` / `BookDetailsSheet` shape — grabber, leading back control,
centered serif title, trailing action slot). This is a translation of the depicted shell into the
existing Compose vocabulary, not a new surface. Concretely:

- Leading control renders the design's back affordance labelled for its parent (`Settings`).
- **Android system back** must invoke the *same* dismissal action — the design has no system-back
  concept, and leaving two divergent dismissal paths is a defect, not a design choice.
- The trailing slot holds the share action, hidden in loading/empty exactly as `DiagLogViewer` does.

**(b) The degraded-source state — deliberately NOT new UI.** If capture is unavailable (logcat
denied *and* the ring is empty), the design's empty state still reads *"VReader records errors and
key events as you read. Entries appear here automatically — nothing to turn on."* That is
inaccurate in the degraded case. But inventing alternative copy is exactly what rule 51 forbids,
and this is a rare state. Decision:

- The viewer renders the **designed** empty state verbatim. No invented copy. (Rule 51 admits no
  "small copy tweak" exemption.)
- The availability signal is surfaced where it is *ours* to spec and where it actually helps the
  person triaging the bug: the **export payload header** (a text file, not designed chrome) gains a
  `capture source:` line — `logcat + breadcrumbs` or `breadcrumbs only (platform log unavailable)`.
- **FILED as GH #2022** (*"Design needed: Diagnostics capture-unavailable empty state for feature
  #164"*, labels `enhancement` + `needs-design`, OPEN) — filed rather than deferred because *both*
  round-2 auditors flagged it independently, which outweighed the author's original "defer" call.
  An implementer picking up WI-6b should read **#2022** before touching the empty state.
  Rationale for filing rather than deferring: the plan
  itself calls the designed copy *"a LIE if the source is dead"*, and shipping a screen that tells a
  user *"entries appear here automatically"* when capture is dead is a user-facing falsehood — that
  is a design gap the moment WI-6b ships, not a future enhancement.
- **This does NOT block WI-6b.** The designed empty state ships as-is; the issue tracks replacing it
  with a designed availability treatment. If the design lands before WI-6b, WI-6b implements it.

### 6.6 Loading-state subtitle

Design **S1** shows `OSLogStore · com.vreader.app` — an iOS type name. The Android string is
`logcat · com.vreader.app` (same slot, same typography, platform-true content).

---

## 7. Work-item sequencing

10 WIs (WI-6 split into 6a/6b at Gate-2 M6). **WI-1 … WI-7 are shippable now → row `DONE`.
WI-8 and WI-9 are blocked on #171 → row `VERIFIED`.** WI-1 is a hard feasibility gate (§2): if it
fails, STOP and escalate on §2's go/no-go before starting WI-4.

```yaml
id: WI-1
tier: foundational
depends: []
blocked_by: []
# Gate-2 High: write-sets are EXPLICIT FILES, never the bare diagnostics/ subtree — WI-1 and WI-2
# both have depends: [] and would otherwise be dispatch-eligible against an overlapping area
# (rule 48 "one writer per file/area"). scripts/check-write-set.sh matches a prefix exactly or as
# a "/"-terminated subtree, so a subtree entry silently swallows another WI's files.
writes:
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsLevel.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsLogEntry.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsLogSource.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/LogcatLineParser.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/LogcatDiagnosticsSource.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/DiagnosticsLevelTest.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/LogcatLineParserTest.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/diagnostics/LogcatSelfReadConnectedTest.kt
tests:
  - DiagnosticsLevelTest                    # JVM
  - LogcatLineParserTest                    # JVM — the pure half, exhaustive
  - LogcatSelfReadConnectedTest             # CONNECTED — THE FEASIBILITY GATE
acceptance:
  - DiagnosticsLevel.fromPriorityChar maps V/D/I/W/E/F and returns null for 'S' and unknown chars.
  - Parser reads `-v uid -v threadtime -v year -v UTC` lines into
    (timeMillis UTC, level, tag, message, sequenceId).
  - MARKER PARSE + STRIP (Gate-2 R3 Medium — v3 specified the marker contract in section 4.1 but
    never required it in WI-1's acceptance, so the dedupe contract could pass tests unimplemented):
    a message beginning with the VLog marker «v<N>» parses N into sequenceId AND removes the marker
    from `message`; a message with no marker yields sequenceId == null with `message` unchanged;
    a malformed marker («v», «vabc») is treated as ordinary message text, NOT stripped.
  - NO entry reaching the store retains a marker — asserted over a mixed fixture, so the marker can
    never surface in the viewer or the exported payload.
  - Parser SKIPS "--------- beginning of main|system|crash|kernel" divider lines.
  - Parser APPENDS an unparseable continuation line to the previous entry's message (stack traces),
    and DISCARDS a leading continuation with no preceding entry.
  - Parser DROPS every row whose uid column != ownUid (the READ_LOGS-granted-via-adb hazard).
  - Parser tolerates, with a SPECIFIED expected output for each (not merely "does not crash"):
    empty input; an empty tag; an empty message; a CJK message; a 4068-byte message at the logd
    payload cap; CRLF line endings.
  - TAG/MESSAGE SPLIT IS DISAMBIGUATED (Gate-2 Medium) — under -v threadtime the separator is ": ",
    so a tag containing ':' is genuinely ambiguous and "tolerates" would define no expected output
    (a test could pass under any behavior). RULE: the FIRST ": " after the level column terminates
    the tag; everything after it is the message. Fixtures assert the exact (tag, message) split for
    a tag with ':', a tag with spaces, and a message that itself contains ": ".
  - LogcatSelfReadConnectedTest runs INSIDE the app process (untrusted_app, NOT run-as):
    writes a unique nonce line via android.util.Log.w, execs the source, and asserts it is read back.
  - NOT TIMING-FLAKY (Gate-2 Medium) — the Log -> logd -> reader round trip is asynchronous, so the
    test POLLS: re-exec the source until the nonce appears or a 5s budget expires, then fail. A bare
    single-shot read is a documented flake class on this project (#125/#133).
  - The uid assertion is CONDITIONAL on a non-empty result: "every returned entry has uid ==
    Process.myUid()" passes VACUOUSLY on [] — the exact outcome the gate exists to detect. The gate
    therefore asserts BOTH (a) the nonce was found, and (b) all entries carry our uid.
  - UID COLUMN RENDERING (Gate-2 Medium) — `logcat -v uid` may print a NUMERIC uid (10209) or a
    SYMBOLIC one (u0_a209) depending on build/uid; the plan's section-2 sample only ever showed a
    numeric SYSTEM uid (1000). A parser that integer-compares against a symbolic uid would drop
    100% of rows and silently degrade the whole feature to the ring buffer with NO error. The parser
    MUST accept both renderings (`\d+` and `u<user>_a<appid>`, with appid = uid - 10000 per user),
    with a LogcatLineParserTest fixture for each, and the connected gate asserts which form this
    device produced.
  - The source consumes stdout with stderr redirected into it (redirectErrorStream) and enforces
    processTimeoutMs.
  - TIMEOUT/REAP PATH (Gate-2 M4) — on timeout the source CLOSES the streams, calls destroy(), then
    destroyForcibly() if the process is still alive, and ALWAYS waitFor()s to reap it. Asserted with
    an injected fake Process that ignores destroy(): the call still returns within the budget AND
    destroyForcibly() was invoked AND no drain thread is left running.
  - The source returns SourceResult.Unavailable (never throws, never returns Available) when exec
    fails, the binary is missing, or the timeout fires; it returns Available(emptyList()) only when
    logcat genuinely produced no matching rows. These two cases MUST be distinguishable.
  - The source never reads more than maxLines rows or maxBytes bytes.
  - The source runs entirely on the injected ioDispatcher (asserted with a TestDispatcher).
  - FEASIBILITY GATE — LogcatSelfReadConnectedTest is a HARD gate, not an informational test.
    It must be run on a REAL emulator (scripts/run-android-tests.sh, ANDROID_SERIAL set) as part of
    WI-1's own PR, NOT deferred to Gate 5. A compile-only or skipped run does NOT satisfy WI-1.
  - The test must assert read-back of a line written IN THE SAME PROCESS via android.util.Log,
    with a unique nonce in the message, so a stale buffer entry cannot produce a false PASS.
  - The test must NOT use run-as, adb, ProcessBuilder("su"), or any shell indirection — it runs as
    the instrumented app process or it proves nothing.
  - If the test FAILS: WI-1's PR does not merge as-is. STOP and escalate to the user with plan
    section 2's "Lost" table, for a go/no-go on the ring-buffer-only feature. Do NOT proceed to WI-4.
    Do NOT request READ_LOGS, add a su/shell path, or relax the test to make it pass.
notes: >
  This WI exists to make the feature's central platform assumption fail EARLY and LOUDLY.
  The plan's section-2 evidence came from `run-as` (SELinux runas_app, carrying supplementary
  groups 1007/1011 a real app lacks); this test is the first observation of the real
  untrusted_app domain, and it decides whether WI-2..WI-9 are worth building.
```

```yaml
id: WI-2
tier: foundational
depends: []
blocked_by: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsRedactor.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/DiagnosticsRedactorTest.kt
tests:
  - DiagnosticsRedactorTest                 # JVM — the security gate
acceptance:
  - All 8 iOS rules ported and asserted with the SAME shapes DiagnosticsRedactorTests.swift covers.
  - 'Authorization: Bearer X' and 'Authorization: Basic X' redacted, quoted AND unquoted, and in a
    serialized "Authorization":"Basic …" JSON shape.
  - Keyed secrets (x-api-key, api_key, api-key, access_token, refresh_token, client_secret, token,
    password, secret) redacted with a QUOTED value containing spaces/newlines (consume to closing quote)
    and with an UNQUOTED value (consume to delimiter).
  - sk-… / sk-proj-… and 3-segment JWTs redacted.
  - scheme://user:pass@host -> scheme://user:‹redacted›@host (host and user preserved).
  - Android paths redacted: /data/user/0/com.vreader.app/…, /data/data/…, /storage/emulated/0/…, /sdcard/….
  - content:// URI path redacted, authority preserved.
  - redact() is IDEMPOTENT — redact(redact(x)) == redact(x) for every fixture.
  - NEGATIVE cases (no over-redaction): a bare SHA-256 hex digest, a fingerprintKey, a Room row id,
    a version string, and an ordinary sentence containing the word "token" with no delimiter are UNCHANGED.
  - A message with no secret is returned byte-identical.
  - Empty string, a 1 MB message, and a CJK/RTL message do not throw.
  - REAL-SHAPE VECTORS — each drawn from an actual credential path in THIS app, asserted verbatim:
      * WebDavClient/OpdsClient  -> 'Authorization: Basic dXNlcjpwYXNzd29yZA==' (base64 user:pass)
      * OpenAiCompatibleProvider -> 'Authorization: Bearer sk-proj-AbC123...'
      * AnthropicProvider        -> 'x-api-key: sk-ant-api03-AbC123...'
      * OPDS/WebDAV URL creds    -> 'https://alice:hunter2@dav.example.com/remote.php/dav/'
      * app-private path         -> '/data/user/0/com.vreader.app/files/books/foo.epub'
      * MULTI-USER path          -> '/data/user/11/com.vreader.app/files/…' (the digit is NOT
        hard-coded to 0 — a work-profile/secondary user must redact too)
      * shared storage           -> '/storage/emulated/0/Download/foo.epub' and '/sdcard/foo.epub'
      * SAF URI                  -> 'content://com.android.providers.downloads.documents/document/msf%3A1000'
      * a stack trace line embedding a URL WITH a query string carrying a key
        (e.g. 'https://api.example.com/v1/chat?api_key=abc123') — the query form must redact
      * CAMEL-CASE ENCRYPTED FIELDS (the iOS alternation does NOT match these — see section 6.1):
        'encryptedApiKey=AAAAFGh...', 'encryptedPassword: AAAAFG...', and a serialized entity dump
        'WebDavServer(id=3, url=https://dav/, username=alice, encryptedPassword=AAAAFGh...)'
        — the encrypted blob must be redacted while id/url/username survive
      * a Room/entity toString() containing BOTH a plain and an encrypted credential field
  - For EVERY vector above the assertion is two-sided: the secret substring is ABSENT from the output
    AND the surrounding diagnostic context (host, scheme, HTTP status, exception class) is PRESENT —
    over-redaction that destroys diagnosability is a failure too, just a safer one.
```

```yaml
id: WI-3
tier: foundational
depends: [WI-1]
blocked_by: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/VLog.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsCategory.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsCategoryBounding.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/RingBufferDiagnosticsSource.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/CompositeDiagnosticsSource.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/PdfDocument.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/share/BookShareIntent.kt
  - android/app/src/main/kotlin/com/vreader/app/search/SearchIndexCoordinator.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/RingBufferDiagnosticsSourceTest.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/VLogTest.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/CompositeDiagnosticsSourceTest.kt
  - scripts/__tests__/check-android-log-containment.sh    # additive; see acceptance
tests:
  - RingBufferDiagnosticsSourceTest         # JVM
  - VLogTest                                # JVM
  - CompositeDiagnosticsSourceTest          # JVM
acceptance:
  - Ring buffer evicts oldest-first at capacity and never exceeds it (assert at capacity+1 and capacity*3).
  - Ring buffer returns oldest→newest and honours `limit` and `sinceMillis`.
  - Ring buffer is safe under concurrent record() from multiple threads (no lost/duplicated entry,
    no ConcurrentModificationException while a read is in flight).
  - VLog.w/i/d/e records into the installed sink with the DiagnosticsCategory.tag as category.
  - VLog with a Throwable appends the stack trace to the message.
  - VLog before install() does not throw and does not record.
  - VLog assigns each entry a MONOTONIC sequence id and emits a compact marker carrying it into the
    android.util.Log message, so the composite can identity-match the two representations.
  - TAG CHANGE (Gate-2 M7, deliberate) — VLog emits to android.util.Log with tag =
    DiagnosticsCategory.tag ("Reader"), NOT the old per-class tag, AND prefixes the original class
    name into the message body ("[FoliateBridge] ..."). Both asserted, so the break is tested.
  - CompositeDiagnosticsSource MERGES primary + secondary entries when primary is Available,
    including when primary is Available(empty) — ring entries are never hidden by a sparse logcat.
  - CompositeDiagnosticsSource returns ONLY secondary entries when primary is Unavailable, and
    never propagates an exception.
  - CompositeDiagnosticsSource DEDUPES by VLog sequence id, not by (time,tag,message) equality:
    an event present in BOTH sources appears exactly once, and two genuinely distinct entries with
    byte-identical text and timestamp both survive.
  - Merged output is ordered oldest→newest across sources.
  - LOG FORWARDING IS ASSERTED ON THE LOG, NOT THE RING (Gate-2 M) — observing the ring sink proves
    only that the ring recorded it. Assert the forward with Robolectric ShadowLog (or an injectable
    Log seam in VLog recording (priority, tag, message)): after a VLog.w call, ShadowLog.getLogs()
    contains an entry with the expected priority + category tag + class-prefixed message. The
    section-10 backward-compat guarantee rests on THIS assertion.
  - All 6 migrated call sites compile and route through VLog (asserted per site).
  - NO production source outside VLog.kt references android.util.Log — enforced by a check in
    scripts/__tests__/ (a grep in an acceptance bullet is not a gate; nothing runs it). The check
    must match BOTH the qualified `android.util.Log.` form AND the short `Log.w(` form with an
    `import android.util.Log` — 4 of the 6 existing sites use the short form.
```

```yaml
id: WI-4
tier: foundational
depends: [WI-1, WI-2, WI-3]
blocked_by: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsLogStore.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/DiagnosticsLogStoreTest.kt
tests:
  - DiagnosticsLogStoreTest                 # JVM
acceptance:
  - load() returns [] (never throws) when the source reports SourceResult.Unavailable.
  - The store EXPOSES source availability (e.g. `lastLoadDegraded`) so the viewer can distinguish
    "log genuinely empty" from "capture unavailable" — the design's empty state claims "Entries
    appear here automatically", which is a LIE if the source is dead. See section 6.5.
  - load() trims to the most recent maxEntries when the source returns more.
  - load(limit) clamps to max(0, min(limit, maxEntries)) — a NEGATIVE limit yields [] and does not throw
    (the iOS Gate-4 finding, ported).
  - categories() returns the RAW distinct non-empty categories, sorted (not the chip set).
  - DiagnosticsCategoryBounding.chips() returns AT MOST the designed 7 (+ "All") even when the
    entries carry 40+ distinct raw framework/library tags, ranked by entry count; and an entry
    whose raw category collapsed into the bucket is STILL reachable by filtering on that bucket.
    Asserted with a fixture carrying many raw tags — the guard against a chip row of dozens.
  - exportText() runs EVERY message through DiagnosticsRedactor — asserted with a secret-bearing entry.
  - exportText() header names the entry count with correct singular/plural and CAPTURE_SCOPE_LABEL.
  - exportText() emits one line per entry as `<ISO-8601 UTC> [LEVEL] (category) <redacted message>`.
  - exportText() of an entry with a MULTI-LINE message keeps it parseable (continuation lines indented).
  - exportText([]) returns a header-only string, not an empty string.
  - CAPTURE_SCOPE_LABEL is the single source used by both the export header and (WI-5) the footer.
```

```yaml
id: WI-5
tier: foundational
depends: [WI-4]
blocked_by: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsViewModel.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsUiState.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsDayGrouper.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/DiagnosticsViewModelTest.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/DiagnosticsDayGrouperTest.kt
tests:
  - DiagnosticsViewModelTest                # JVM
  - DiagnosticsDayGrouperTest               # JVM
acceptance:
  - Level filter Errors matches {ERROR, ASSERT}; Info matches {INFO}; Debug matches {VERBOSE, DEBUG};
    All matches everything. WARN is reachable ONLY under All and renders with the debug treatment —
    the section-6.3 interim pending the filed WARN needs-design issue. Explicitly asserted so a
    later change to {WARN,ERROR,ASSERT} is a deliberate, test-breaking decision.
  - Chip counts are computed over ALL loaded entries, category-INDEPENDENT (iOS parity).
  - Level and category filters COMPOSE; an empty result sets a filtered-empty state distinct from
    the plain empty state.
  - Changing either filter RESETS the expanded-row identity.
  - Expanded-row identity is POSITION-based, so two byte-identical entries expand independently.
  - Day sections are newest-first and group by LOCAL calendar day with an injected clock/zone;
    "Today"/"Yesterday" labels resolve against the injected now, not the wall clock.
  - Day grouping is correct across a midnight boundary, a DST transition, and a non-Gregorian locale.
  - footerScope has THREE designed formats, not two (Gate-2 Medium): "<N> entries · recent activity"
    unfiltered; "Showing X of N · <descriptor>" filtered-with-results; and "0 of N entries" for
    FILTERED-EMPTY (vreader-diagnostics.jsx:484 — a distinct grammar, and F3 is an artboard the
    plan cites). All three asserted.
  - DAY-HEADER FORMAT is specified, not left to invention (Gate-2 Medium): the design renders
    uppercase letter-spaced "Today · 10 June" / "Yesterday · 9 June" (:308) — a "· D Month" suffix
    v1/v2 never mentioned. Today and yesterday use those literals; ANY OLDER DAY uses "D Month"
    alone (e.g. "8 June"), since the design never depicts one. Asserted for all three cases.
    If the older-day label is considered undepicted rather than derivable, that is a rule-51
    needs-design filing, not an implementer's choice — flagged for Gate-2 adjudication.
  - exportFileName(now) == "vreader-log-YYYY-MM-DD.txt" with an injected clock (deterministic).
  - isLoading is true across the load() await and false after, including when load() throws.
```

```yaml
id: WI-6a
tier: behavioral
depends: [WI-5]
blocked_by: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsLogRow.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsLevelStyle.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsFilterBar.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsFooter.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsIcons.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsLogRowTest.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsFilterBarTest.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsFooterTest.kt
tests:
  - DiagnosticsLogRowTest                   # CONNECTED
  - DiagnosticsFilterBarTest                # CONNECTED
  - DiagnosticsFooterTest                   # CONNECTED
acceptance:
  - Row renders the meta line as mono timestamp, uppercase level in its functional color, and a
    mono category pill (design A1/A2).
  - Level colors match the design exactly - error #b13e36 light / #e0826f dark, info #3a6f9c /
    #7fb2d9, debug = theme.sub - asserted per level, both themes, in SEPARATE test methods.
  - A collapsed long message is clamped to 3 lines; tapping expands it and reveals "Copy entry".
  - CLIPBOARD REDACTION (Gate-2 CRITICAL, iOS parity - DiagnosticsLogView.swift:173) - "Copy entry"
    puts DiagnosticsRedactor.redact(message) on the clipboard, NOT the raw message. Asserted with a
    secret-bearing entry: the clip contains ‹redacted› and does NOT contain the seeded secret, while
    the surrounding diagnostic context survives.
  - The expanded row still DISPLAYS the full unredacted message on-screen (on-device display is not
    egress); only the clipboard copy is redacted. Both asserted in the same test so the distinction
    cannot silently invert.
  - Day header renders the design's uppercase "Today · 10 June" / "Yesterday · 9 June" shape.
  - Level chips carry counts; the ACTIVE Errors chip takes the error tint while other active chips
    take the inverted-ink pill; inactive chips take the outlined form.
  - The category chip row scrolls horizontally and does not wrap.
  - Footer renders the mono scope line plus the green-dot "Capturing" status.
  - setContent is called at most ONCE per test method (looping themes throws IllegalStateException;
    only the connected run catches it - #134 precedent).
```

```yaml
id: WI-6b
tier: behavioral
depends: [WI-6a]
blocked_by: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsScreen.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsStates.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsNavShell.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsShareButton.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsScreenTest.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsStatesTest.kt
  - scripts/.orphan-surfaces-allow    # see notes — carved out of the section 4.4 scripts exclusion
notes: >
  ORPHAN-SURFACE DEBT (Gate-2 Medium). Merging WI-6b puts a top-level DiagnosticsScreen composable
  in main source with ZERO production call sites until WI-8, which is exactly what
  scripts/check-orphan-surfaces.sh detects. Section 4.4 excludes scripts/ from this feature's
  write-set, which would leave no legal way to record the known, tracked gap — so
  scripts/.orphan-surfaces-allow is explicitly CARVED OUT of that exclusion for a single entry,
  annotated with "#164 pending #171". WI-8 REMOVES the entry as part of its acceptance. This keeps
  the detector honest rather than permanently silenced.
tests:
  - DiagnosticsScreenTest                   # CONNECTED — createComposeRule on …Content
  - DiagnosticsStatesTest                   # CONNECTED
acceptance:
  - Default state composes header + filter bar + day-grouped list + footer (design V1/V2).
  - Loading state renders the spinner + "logcat · com.vreader.app" and HIDES the filter bar,
    the share affordance, and the footer (design S1).
  - Empty state renders the pulse tile + "No log entries yet" and HIDES the filter bar, the share
    affordance, AND THE FOOTER (design S2/S3 — in DiagLogViewer the footer is gated by the same
    `!busy && state !== 'empty'` predicate as the other two, vreader-diagnostics.jsx:469; v1/v2
    omitted the footer and would have rendered "0 entries · recent activity · ● Capturing" on a
    fresh-install screen no artboard depicts).
  - Filtered-empty renders the filter tile + "No matching entries" + a working "Clear filters"
    button that restores the unfiltered list (design F3), and KEEPS the footer.
  - Filtered-empty BODY COPY single-sources the capture-scope label: the design hardcodes "Nothing
    matches {filter} in the last 24 hours." (:372), but "last 24 h" is the window this plan
    deliberately replaces with CAPTURE_SCOPE_LABEL for the footer and export header. The body copy
    uses the SAME label ("Nothing matches {filter} in recent activity.") so all three consumers
    agree — an implementer must not be left to invent a third string.
  - The screen shell mirrors the design's DiagNavSheet - grabber, leading back control, centered
    serif title "Diagnostics", trailing share action (design V1) - using the app's existing sheet
    vocabulary; see section 6.5 for the Android container decision.
  - Android system back invokes the SAME action as the leading back control (single dismissal path).
  - Scrolling to the LAST of 2000 entries succeeds and only a bounded number of rows is composed
    (asserted via a composition counter) — i.e. the list virtualizes. Stated as behavior rather
    than "does not throw" (which any implementation satisfies) or by prescribing the widget.
  - The share action is HIDDEN in the loading and empty states and VISIBLE otherwise (design S1/S2).
```

```yaml
id: WI-7
tier: behavioral
depends: [WI-4, WI-6b]
blocked_by: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsExportWriter.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsFileProvider.kt
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsShareIntent.kt
  - android/app/src/main/res/xml/diagnostics_paths.xml        # NEW file
  - android/app/src/main/AndroidManifest.xml                  # second <provider> only
  - android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/diagnostics/DiagnosticsShareConnectedTest.kt
  - android/app/src/test/kotlin/com/vreader/app/diagnostics/DiagnosticsExportWriterTest.kt
  - android/app/src/test/kotlin/com/vreader/app/AppContainerDiagnosticsWiringTest.kt
forbidden_writes:
  - android/app/src/main/res/xml/file_paths.xml               # section 6.4 — book provider stays books-only
  - android/app/src/main/kotlin/com/vreader/app/reader/share/  # BookShareIntent / BookFileProvider untouched
tests:
  - DiagnosticsExportWriterTest             # JVM (temp dir)
  - DiagnosticsShareConnectedTest           # CONNECTED — real FileProvider resolution
  - AppContainerDiagnosticsWiringTest       # JVM — asserts the container graph
acceptance:
  - Writer creates filesDir/diagnostics/, writes to a ".part" temp and atomically renames (BookImporter precedent).
  - Writer DERIVES the filename from its injected clock; there is no caller-supplied filename
    parameter, and the resolved file is asserted to be a canonical child of the diagnostics dir.
  - Writer PRUNES prior export files so filesDir/diagnostics holds at most 1 export.
  - Writer returns a File whose content is byte-identical to the redacted text (UTF-8, CJK round-trips).
  - Writing twice on the same day overwrites rather than accumulating.
  - FileProvider.getUriForFile succeeds for the export file with authority
    "com.vreader.app.diagnosticsprovider" backed by @xml/diagnostics_paths — proving the NEW
    provider resolves (a missing/mis-scoped root throws IllegalArgumentException, so this test
    genuinely gates the manifest change).
  - NEGATIVE PROVIDER TEST — getUriForFile for the export file against the BOOK provider authority
    "com.vreader.app.fileprovider" THROWS IllegalArgumentException, proving diagnostics did NOT
    widen the book provider's grant scope (the section 6.4 invariant, asserted not assumed).
  - file_paths.xml is byte-identical to its pre-WI state (asserted in review, listed as forbidden_writes).
  - The share Intent is ACTION_SEND, type "text/plain", carries EXTRA_STREAM + FLAG_GRANT_READ_URI_PERMISSION
    and a matching ClipData, and is wrapped in createChooser.
  - shareDiagnosticsIntent RETURNS NULL for a file outside filesDir/diagnostics (its own
    path-traversal guard; BookShareIntent.isInsideBooksDir is NOT widened or reused).
  - The exported file content contains ‹redacted› and NOT the seeded secret (end-to-end leak assertion
    through store -> writer, not just the redactor unit).
  - shareDiagnostics(context, file) — the LAUNCHER — swallows ActivityNotFoundException when no
    receiver exists (BookShareIntent.shareBook precedent). Asserted on the launcher, not on the
    Intent builder, which cannot throw it.
  - WIRING IS FALSIFIABLE, NOT A READING EXERCISE (Gate-2 Medium) — "verified by finding the call
    site" is not a gate; nothing fails if the call is absent. Instead:
    AppContainerDiagnosticsWiringTest builds VReaderApp under Robolectric and asserts that a
    VLog.w() call lands in the container's ring WITHOUT the test calling VLog.install() itself.
    That fails if onCreate() stops installing the sink, which is the actual regression risk.
```

```yaml
id: WI-8
tier: behavioral
depends: [WI-6b, WI-7]
blocked_by: ["#171 (docs/features.md:223) — Settings hub must exist; #171 is itself BLOCKED: needs-design (GH #2018)"]
dispatchable: false        # rule 55 — NOT dispatchable until the write-set below is made concrete
writes:
  - android/app/src/main/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsSettingsRow.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/diagnostics/ui/DiagnosticsEntryConnectedTest.kt
  - scripts/.orphan-surfaces-allow    # REMOVES the WI-6b entry (see acceptance)
  # NOTE: this WI must ALSO edit #171's Settings hub file, whose path does not exist yet.
  # Rule 55 requires files_touched to be a SUBSET of the declared write-set, so this WI is
  # marked dispatchable:false and CANNOT be handed to a lane in its current form.
tests:
  - DiagnosticsEntryConnectedTest           # CONNECTED — from the Settings hub, not from the composable
acceptance:
  - A "Support" group with a "Diagnostics" row (steel #5b6770 tile, pulse glyph, detail
    "View and export app logs") renders in the #171 Settings hub, per design E1/E2.
  - Tapping the row navigates to DiagnosticsScreen with a back affordance to Settings.
  - The test STARTS from the production entry (launch -> Settings -> Support -> Diagnostics),
    never by invoking DiagnosticsScreen directly.
  - The WI-6b entry is REMOVED from scripts/.orphan-surfaces-allow, and
    scripts/check-orphan-surfaces.sh then reports NO orphan for any diagnostics composable —
    i.e. the surface is genuinely reachable, not merely allowlisted.
notes: >
  RULE-55 PRECONDITION (Gate-2 High). A lane's files_touched must be a subset of its declared
  write-set, so an unresolved placeholder path is not a legal write-set entry. Therefore: when
  #171 lands, this plan is REVISED — the exact Settings hub file path is substituted into
  `writes:` and `dispatchable:` flips to true — and only then may WI-8 be dispatched. Until that
  revision, WI-8 runs INLINE (/feature-workflow) or not at all. Do not dispatch it to a lane
  with a placeholder.
  Coordination: the "About VReader" row in design E1 belongs to #171's Support group, not to
  #164. If #171 ships the group, #164 adds only the Diagnostics row.
```

```yaml
id: WI-9
tier: acceptance
depends: [WI-8]
blocked_by: ["#171 (docs/features.md:223), itself BLOCKED: needs-design (GH #2018)"]
dispatchable: false        # rule 55 — orchestrator/verifier work, not a lane
writes: []                 # a VERIFIER returns observations; the ORCHESTRATOR writes the evidence
# Gate-2 Medium: v2 gave a lane `dev-docs/verification/feature-164-*.md`, but rule 55 is explicit
# that the verifier "never writes evidence files, never flips tracker rows" — the orchestrator
# writes them so check_terminal_status_evidence.sh fires where the file lives.
orchestrator_writes:
  - dev-docs/verification/feature-164-<YYYYMMDD>.md
tests:
  - "full acceptance pass on a booted emulator via scripts/run-android-verify.sh"
acceptance:
  - Every acceptance criterion exercised end-to-end from app launch through the SHIPPED UI.
  - The evidence file names the user-visible path taken ("Library -> Settings -> Support ->
    Diagnostics -> share"), per rule 47 Gate 5 "Production reachability".
  - LEAK ASSERTION (must not false-pass) — a UNIQUE NONCE SECRET is deliberately emitted into the
    capture path and then searched for in the exported file. Do NOT rely on "a 401 against a fake
    AI provider": the AI clients set auth headers but do NOT log them (verified — the auth call
    sites carry `// never logged` comments), so a 401 alone may put NO secret into the log and the
    test would pass while proving nothing. Instead emit a nonce of each real shape
    (Authorization Basic, Bearer sk-, x-api-key, url-embedded creds, encryptedApiKey) through a
    controlled VLog/logcat fixture, then assert every nonce is ABSENT and ‹redacted› is PRESENT.
  - The test FAILS if the nonce never entered the capture path at all (assert the unredacted nonce
    is visible in the pre-redaction store contents), so an empty log cannot masquerade as a pass.
  - NON-DEBUGGABLE BUILD CHECK — states what it actually falsifies (Gate-2 Medium; v1/v2's
    "R8/minify" framing was vacuous). android/app/build.gradle.kts declares NO buildTypes block at
    all, so isMinifyEnabled defaults false and there is nothing for R8 to strip; the parser also
    keys on literal DiagnosticsCategory.tag strings, which R8 would not rename. The REAL question a
    non-debug build answers is SELINUX/PLATFORM PARITY: WI-1's gate runs under an instrumented,
    DEBUGGABLE process, and `debuggable` is exactly the attribute that gates `run-as` and can
    correlate with logd/SELinux behavior. So: verify logcat self-read still works on a
    NON-DEBUGGABLE build. If producing one requires buildTypes/signingConfig that do not exist
    today, that config work is IN SCOPE for this WI and must be scoped explicitly — not waved at.
  - If a non-debuggable build cannot be produced, this is recorded as a VERIFICATION GAP in the
    evidence file (the feature may still ship), NOT silently dropped.
  - Row flips DONE -> VERIFIED only after this passes.
```

**PR size estimate**: WI-1 ~350 LOC, WI-2 ~280, WI-3 ~320, WI-4 ~200, WI-5 ~250,
WI-6a ~330, WI-6b ~300, WI-7 ~340, WI-8 ~120, WI-9 docs-only.

---

## 8. Test catalogue

| File | Kind | Covers |
|---|---|---|
| `diagnostics/DiagnosticsLevelTest.kt` | JVM | priority-char mapping, unknown/`S` |
| `diagnostics/LogcatLineParserTest.kt` | JVM | golden lines, dividers, continuations, uid drop, CJK, 4068 B cap, CRLF, empty |
| `diagnostics/LogcatSelfReadConnectedTest.kt` | **connected** | **the §2 feasibility gate** — in-process self-read, uid invariant, timeout/destroy |
| `diagnostics/DiagnosticsRedactorTest.kt` | JVM | the 11 redaction rules in §6.1's table, the 11 real-shape vectors in WI-2, idempotency, and 5 negative (no-over-redaction) cases incl. the fingerprint key surviving |
| `diagnostics/RingBufferDiagnosticsSourceTest.kt` | JVM | eviction, ordering, limit/since, thread safety |
| `diagnostics/VLogTest.kt` | JVM | category tagging, throwable, pre-install no-op |
| `diagnostics/CompositeDiagnosticsSourceTest.kt` | JVM | merge when primary Available (incl. empty), secondary-only when Unavailable, seq-id dedupe, cross-source ordering |
| `diagnostics/DiagnosticsLogStoreTest.kt` | JVM | trimming, negative limit, redacted export, header, multi-line |
| `diagnostics/DiagnosticsViewModelTest.kt` | JVM | filter sets, counts, compose, expand reset, footer, filename |
| `diagnostics/DiagnosticsDayGrouperTest.kt` | JVM | midnight, DST, locale, Today/Yesterday |
| `diagnostics/ui/DiagnosticsLogRowTest.kt` | **connected** (WI-6a) | clamp/expand, Copy entry, level colors both themes, day header |
| `diagnostics/ui/DiagnosticsFilterBarTest.kt` | **connected** (WI-6a) | chip counts, Errors tint, category h-scroll |
| `diagnostics/ui/DiagnosticsFooterTest.kt` | **connected** (WI-6a) | scope line + Capturing dot |
| `diagnostics/ui/DiagnosticsScreenTest.kt` | **connected** (WI-6b) | shell (grabber/back/title/trailing), system back parity, 2000-row scroll |
| `diagnostics/ui/DiagnosticsStatesTest.kt` | **connected** (WI-6b) | default / loading / empty / filtered-empty + Clear filters |
| `diagnostics/DiagnosticsExportWriterTest.kt` | JVM | atomic write, prune, UTF-8/CJK, overwrite |
| `diagnostics/DiagnosticsShareConnectedTest.kt` | **connected** | FileProvider resolution of the new root, intent shape, guard, end-to-end leak assertion |
| `AppContainerDiagnosticsWiringTest.kt` | JVM | container graph + `VLog.install` call site |
| `diagnostics/ui/DiagnosticsEntryConnectedTest.kt` | **connected**, #171-gated | production-entry navigation |

Conventions: JVM tests are `@RunWith(RobolectricTestRunner::class)` where a `Context` is needed
(`robolectric.properties` pins `sdk=34`). The **five UI** connected tests use `createComposeRule()`
on the `…Content` composable (house convention; `createAndroidComposeRule` is used zero times in
this repo, `createComposeRule()` in 47 files). The **non-UI** connected tests differ and are not
Compose-rule tests: `LogcatSelfReadConnectedTest` and `DiagnosticsShareConnectedTest` use
`InstrumentationRegistry` targetContext, and `DiagnosticsEntryConnectedTest` launches an Activity.
Runners: `scripts/run-android-tests.sh` / `scripts/run-android-verify.sh` — never a bare `./gradlew`
(rule 52 Cause D), with `ANDROID_SERIAL=emulator-5554`.

---

## 9. Risks + mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Production `untrusted_app` cannot connect to logd's `logdr` socket or exec `/system/bin/logcat` (§2: evidence came from `runas_app`, a different SELinux domain) | **High** | WI-1's connected test is the gate; `CompositeDiagnosticsSource` + `VLog` ring buffer is the floor; §2's written go/no-go governs the escalation |
| R2 | OEM/ROM variance in logd policy | Medium | Same floor as R1; source returns `[]` rather than throwing, so the viewer degrades to the ring buffer silently |
| R3 | **Secret leaks into the export** — the redactor is the only barrier (§6.1) | **High** | Dedicated WI-2 with 12 leak shapes + idempotency + negatives; WI-7 asserts end-to-end that a seeded secret is absent from the written file; WI-9 repeats it with a **controlled unique-nonce fixture per leak shape** plus a pre-redaction-presence assertion — explicitly NOT "a real 401", which cannot be relied on because the AI clients never log their auth headers (Gate-2 High) |
| R4 | `Runtime.exec` deadlock when the stdout pipe fills | Medium | `redirectErrorStream(true)` + single-reader drain + `processTimeoutMs` + `destroy()`; asserted in WI-1 |
| R5 | 2 MiB ring rotates away the interesting entries before the user opens the screen | Medium | Documented in the `"recent activity"` label; the ring-buffer floor retains vreader's own entries independent of logd rotation |
| R6 | logd truncates payloads at 4068 B — long stack traces arrive split | Medium | Parser's continuation-line handling; explicit 4068-byte test fixture |
| R7 | Export file accumulates in `filesDir` | Low | Writer prunes to at most 1 export; asserted |
| R8 | R8/minify in release alters tags the parser keys on | Medium | WI-9 verifies on a release-configured build (explicit acceptance line) |
| R9 | **The reachability chain is indefinite, not a slip** — #164 `VERIFIED` ⇐ #171 `DONE` ⇐ GH #2018 *design delivered*. #171 is `BLOCKED: needs-design (#2018)`, and #2018 is an OPEN `needs-design` issue with no bundle yet, which per rule 51 only the user can carry through claude.ai/design | **High** (raised from Medium at Gate-2 — v1 rated this as a schedule risk, which understated it) | **Accepted and declared** (§3). WI-1–7 deliver standalone value and merge independently; only WI-8/9 wait. The row parks at `DONE` for as long as the chain takes, which may be indefinitely — that is a known, stated outcome of starting this feature now, not a surprise. If parking at `DONE` is unacceptable, the correct response is to prioritise #2018's design, not to weaken this feature's Gate-5 bar |
| R10 | #171 and #164 both edit the Settings hub file | Medium | WI-8 deliberately does **not** pre-declare #171's file path; sequenced strictly after #171 lands (rule 48 one-writer-per-file) |
| R11 | Connected Compose tests merged "compile-only" during foundational WIs are unverified until Gate 5 — a documented recurrence on this project (#133: 6/14 were RED when first actually run) | **High** | Every connected test in this plan runs on the emulator in ITS OWN WI, not deferred to WI-9; budget a test-hardening pass before flipping VERIFIED |
| R12 | `setContent` called twice in a themed loop → `IllegalStateException` (recurred on #134) | Low | Encoded as a WI-6a acceptance line: separate test methods per theme |

---

## 10. Backward compatibility

- **No schema change.** No Room entity, no migration, no DAO. `VReaderDatabase` is untouched.
- **No backup-format change.** No new backup section, no `contracts/` change, no `:identity` change;
  `contracts/vectors/` is unaffected. iOS backups restore on Android exactly as today.
- **No DataStore addition.** The viewer holds filter state in the ViewModel only — nothing persists,
  so there is no new `*.preferences_pb` name to clash with the four at `VReaderApp.kt:350-353`.
- **`file_paths.xml` is UNCHANGED.** A *second* provider (`DiagnosticsFileProvider`, authority
  `${applicationId}.diagnosticsprovider`, backed by a new `@xml/diagnostics_paths`) is declared
  alongside the existing one (§6.4). Existing book-share URIs keep resolving; the `books` root and
  `BookFileProvider`'s DISPLAY_NAME override are untouched — literally, not just in intent.
- **The 6 migrated `Log.w` sites keep emitting to `android.util.Log`** through `VLog`, but the
  **logcat TAG changes** — a deliberate, breaking-for-developers change flagged by Gate-2 (M7).
  Today's tags are per-class (`PdfDocument`'s `TAG`, `"ReaderActivity"`, `"FoliateBridge"`,
  `"BookShare"`, `"SearchIndex"`); after migration the tag is the `DiagnosticsCategory` tag
  (`"Reader"`, `"Search"`, …). This is intentional: it is what makes logcat-sourced and
  ring-sourced entries share ONE category vocabulary, which is the whole basis of the design's
  category chips (§2). Consequences, stated rather than discovered:
  - Any developer or script filtering logcat by an old tag (`adb logcat -s FoliateBridge`) must
    switch to the category tag. No shipped contract depends on these tags — they are our own
    debug output, not an API — so nothing user-facing breaks.
  - The original class name is **not lost**: `VLog` prefixes it into the message body
    (`"[FoliateBridge] console[...]"`), so grep-by-class still works and the diagnostic detail
    survives the tag change.
  - WI-3 asserts the new tag AND the preserved class prefix, so the change is tested, not assumed.
- **Older Android versions**: `minSdk = 26`. `logcat -v uid` requires API 24+ and `--pid` API 24+;
  both are below the floor. No new permission is requested, so no install-time or runtime prompt change.
- **Uninstall/downgrade**: exports live in app-private `filesDir` and vanish with the app; nothing
  leaks into shared storage.

---

## 11. Known limitations (explicitly accepted)

1. Book titles/filenames are not redacted (§6.1) — iOS #96 parity; redacting them would gut the log's value.
2. No crash/ANR capture. A fatal ART crash is in logcat and *may* survive in the ring for the next
   launch, but there is no `UncaughtExceptionHandler` hook. Follow-up candidate.
3. No log-level configuration UI, no "clear log" action, no auto-refresh — none is designed.
4. Capture scope is bounded by logd's 2 MiB uid-filtered ring plus a 500-entry in-process buffer.
5. The Android level vocabulary has no designed `WARN` treatment (§6.3). Interim: warn-level entries
   appear only under the `All` chip with the `debug` treatment; a `needs-design` issue is filed.
6. **Bare-value secret interpolation is not fully redactable** (§6.1). `VLog.w(cat, "… $encrypted")`
   emits a credential with no key name, which no keyed rule can match and which a blanket base64
   rule would over-redact. Mitigated by a SecretCipher-framing rule where possible; otherwise the
   real control is logging discipline — never interpolate a credential field — which the `VLog`
   facade makes reviewable in one place.
7. The degraded (capture-unavailable) empty state shows the designed copy, which claims entries
   appear automatically; availability is surfaced only in the export header until the filed
   `needs-design` issue is resolved (§6.5).

---

## 12. Revision history

### Gate-2 record (summary — detail in the version entries below)

| Pass | Auditor | Verdict | Disposition |
|---|---|---|---|
| Round 1 | Codex `gpt-5.5`/high | C=0 **H=4** M=8 L=3 | all 15 fixed → v2 |
| Round 2a | Codex `gpt-5.5`/high | C=0 **H=3** M=8 L=0 | all fixed (1 fixed mid-run) → v3 |
| Round 2b | independent per-claim adversarial fan-out | **C=2** H=6 M=20 L=8 | all fixed; 2 stale (already fixed mid-flight) → v3 |
| Round 3 | Codex `gpt-5.5`/high | C=0 **H=1** M=3 L=1 | `RUN-CODEX RESULT: SUCCEEDED`. All 4 C/H/M **fixed**; the L was an environment artifact (see below) |

**GATE-2 STATUS: NOT CERTIFIED CLEAN — every known finding is fixed, but no pass has returned a
clean verdict on the final text.** Rule 47 caps the gate at 3 rounds and round 3 has been used, so
**no round 4 was run.** Round 3's four C/H/M findings were each verified against source and fixed:

| R3 finding | Verified? | Fix |
|---|---|---|
| **HIGH** — `categories()` "drives the chip row" contradicted `DiagnosticsCategoryBounding`, so raw framework tags could still render dozens of chips | yes — the plan did say both | separated raw `categories()` from the bounded `chips()`; WI-4 asserts the cap AND that collapsed entries stay filterable |
| **MEDIUM** — the SecretCipher "fixed IV+tag length prefix" mitigation is impossible | yes — `SecretCipher.kt:35` returns `base64(iv + ct)`, documented `:25`, **no prefix** | mitigation withdrawn; downgraded to an explicitly accepted limitation with `VLog` discipline as the only real control |
| **MEDIUM** — "this blocks nothing" hid that the WARN interim still prints a 4th token, and on this codebase that is the common case (all 6 sites are `Log.w`) | yes | interim now renders warn rows with the `DEBUG` token (stays inside the 3-token vocabulary); option (ii) block-on-#2021 offered as the user's switch |
| **MEDIUM** — WI-1 acceptance never required parsing/stripping the `«v<N>»` marker, so the dedupe contract could pass tests unimplemented | yes | marker parse/strip/malformed cases added to WI-1, plus "no entry reaching the store retains a marker" |
| *LOW* — auditor could not verify GH #2018 is OPEN (`error connecting to api.github.com`) | n/a — environment | independently verified locally: #2018 OPEN, `enhancement`+`needs-design`; also #2021/#2022 verified OPEN |

**Recommendation: ACCEPT and proceed to Gate 3, with one condition** — dispatch **WI-1 alone first**,
and let its Gate-4 implementation audit serve as the independent pass on this plan's engine
assumptions. Rationale: the residual risk is now *documentation-consistency* risk (do the last four
edits cohere?), not *design* risk. Every design question was adjudicated with evidence across four
passes, and the gate's two most serious findings — unredacted clipboard egress and the
mis-identified #171/#2018 chain — are fixed and re-verified against source. The trend supports this:
H=4 → H=3 → H=1, with round 3's findings all narrow and local.
*If a clean verdict is required before any code is written*, the cheap alternative is one more Codex
pass on the final text — but that is a fourth round and rule 47 forbids it without an explicit
user decision to override.

### Correction — the plan committed the defect class it was written to prevent

**v3 asserted that two rule-51 `needs-design` issues "are filed as part of this plan". They did not
exist.** A check of `gh issue list --state all` showed the newest issue in the repo was #2018;
nothing matched either surface. §6.3 and §6.5 likewise phrased "File the issue NOW" as a *completed*
decision. The issues were filed afterwards, by the reviewer, as **#2021** (WARN treatment) and
**#2022** (capture-unavailable empty state); §3.1/§6.3/§6.5 now cite those real numbers.

This is recorded rather than quietly patched because it is **the same shape as the failure this
plan's own §3 is about**: `dev-docs/plans/20260622-feature-118-android-ai-provider-chat.md:53-55`
claimed *"a production Settings entry is wired"* when it was not, and that class of unverified state
claim is what left four features `VERIFIED` with UI no user could open — the reason rule 47 Gate 2
now mandates wiring-claim verification, and the reason #171 exists.

The lesson generalises past GH issues: **a plan may assert an obligation is discharged only after
verifying it.** A pending obligation stated as pending gets re-checked; one stated as done does not.
Notably, the same author-side discipline that caught the `BookFileProvider` scoping defect and the
`file_paths.xml` overstatement was *not* applied to the plan's own side effects — verification was
aimed outward at the codebase and not at the plan's claims about its own actions.

**Audit-cost note for the next planner (calibration).** This plan consumed **four audit passes**
(3 Codex + 1 adversarial fan-out) on a **Medium** feature. Rule 47's audit-count table calls for
**one** plan audit at this size. The extra passes did pay — the fan-out found the gate's only
CRITICAL, which the broad Codex passes missed twice — but that cost does not scale across the
remaining phase-4 backlog. **Default for future features: run ONE Codex round; escalate to a second
round, and to the adversarial fan-out, only when a round returns High-or-above.** This plan's own
round 1 returned H=4, which under that rule would itself have justified the escalation — so the
policy would not have missed anything here.

- **v3 (2026-08-04) — Gate-2 round 2 applied (two independent auditors).** This round paired the
  broad Codex audit with a per-claim adversarial fan-out, per the project's deep-AND-broad gating
  practice; they caught complementary defect classes and the fan-out found the round's only
  CRITICAL.
  - **Auditor A** — Codex `gpt-5.5`/high, `scripts/run-codex.sh`, `RUN-CODEX RESULT: SUCCEEDED`.
    Log: `scratchpad/f164-gate2-r2.txt`. Verdict **C=0 H=3 M=8 L=0** (regression-check of the v2
    fixes + fresh audit).
  - **Auditor B** — independent per-claim fan-out with a 36-row claim-verification table. Verdict
    **C=2 H=6 M=20 L=8** (audited v1/v2; 2 findings were already fixed mid-flight and are recorded
    as stale).
  - **CRITICAL (Auditor B) — clipboard egress was unredacted.** "Copy entry" put the raw message on
    the clipboard while only `exportText()` redacted. iOS already redacts on copy
    (`DiagnosticsLogView.swift:173`); the v1 parity claim rested on reading `Services/Diagnostics/`
    (298 lines) but **not** `Views/Settings/Diagnostics/`, where that call site lives. Fixed: §6.1
    now states redaction applies at EVERY egress, and WI-6a asserts the clip is redacted while
    on-screen display stays full. This was the single most consequential finding of the gate — a
    user following "share your diagnostics" could have pasted a live `Bearer sk-…` into a public
    issue.
  - **HIGH** — the hard dependency was mis-cited: GH #2018 is the *design* issue, **not** #171's
    mirror; #171 has no GH mirror and is itself `BLOCKED: needs-design (#2018)`. The real chain is
    **#164 `VERIFIED` ⇐ #171 `DONE` ⇐ #2018 design delivered**, and R9 is raised Medium → **High**
    as an indefinite block rather than a schedule slip.
  - **HIGH** — `DiagnosticsLogEntry` had no `sequenceId`, so v2's identity-dedupe design was not
    representable in its own API. Added, with marker placement (leading, survives tail truncation),
    null-means-distinct fail-open semantics, and mandatory marker stripping before display/export.
  - **HIGH** — the `DiagnosticsCategory` enum contradicted the justification built on it: it dropped
    the design's `Persistence` and `DebugBridge` and invented `Search`/`Data`/`Share`. Reconciled to
    the designed vocabulary, and a `DiagnosticsCategoryBounding` rule now caps the chip row at the
    designed 7 — without it, raw framework/library logcat tags would render dozens of chips.
  - **HIGH** — write-sets used bare `diagnostics/` subtrees that overlapped dependency-free WIs
    (rule 48 one-writer-per-area; `check-write-set.sh` subtree semantics). Every WI now declares
    explicit files.
  - **HIGH** — §4.2 named no file for the design's nav shell, share button, or custom pulse glyph,
    while WI-6 asserted behavior of the share affordance. All three added.
  - **HIGH/MEDIUM (stale)** — WI-7's provider strategy and §10's `file_paths.xml` bullet were
    flagged by both auditors; the former was fixed mid-round-1, the latter fixed during Auditor A's
    run. Both now consistent in all four places (§4.1/§4.3/§4.4/§6.4/§10/WI-7).
  - **MEDIUM (selected)** — WARN mapping re-adjudicated: rendering `ERROR` for warnings was rejected
    as misreporting severity, a `needs-design` issue is filed, and the interim confines WARN to the
    `All` chip so the Errors count stays honest; the degraded empty state now files its
    `needs-design` immediately (both auditors agreed, overriding the author's "defer"); the path
    rule was over-redacting the **fingerprint key** (the handle every book bug is filed against) and
    now preserves the trailing `books/` segment; bare-value secret interpolation acknowledged as
    *not* covered rather than falsely claimed; `ShadowLog` replaces a ring-sink assertion that could
    not prove logcat forwarding; the WI-7 wiring criterion became a falsifiable Robolectric test;
    the uid column must accept both numeric and `u0_aNNN` renderings (a wrong guess would silently
    degrade the whole feature); WI-1's gate now polls (anti-flake) and its uid assertion is no
    longer vacuous on `[]`; the empty state hides the footer; the filtered-empty footer and body copy
    and the day-header format are specified; `version.properties` and WI-9's evidence file were
    reassigned from lanes to the orchestrator per rule 55; the orphan-surface allowlist was carved
    out of the `scripts/*` exclusion so the WI-6b→WI-8 gap is tracked rather than silently ignored.
  - **§2 reasoning corrected** — tests 3/7 actually *discriminate against* the supplementary-group
    hypothesis the v2 caveat leaned on (logd grants an unfiltered stream to `AID_LOG` holders, yet
    our reader was filtered). The real residual risk is named: SELinux `logdr` socket connect and
    `system_file` exec under `untrusted_app`.
  - **§6.4 justification softened** — the "widens scope just as surely" equivalence and the "working
    by luck" framing were both **overstated and are withdrawn**; the separate-provider decision now
    rests on blast-radius isolation and removing a latent coupling, which is what the evidence
    supports. The decision itself is unchanged.
  - **LOW** — line citations corrected (`AndroidManifest.xml:48-56`, `BookImporter.kt:54-95`,
    `MainActivity.kt:46-48`, `StatsViewModel.kt:21-25`); "five `// never logged`" corrected to eight
    (only two adjacent to a header write, one of them `x-api-key`); "48 sites" corrected to 23
    files; redactor shape counts normalized; the `LazyColumn` tautology restated as virtualization
    behavior; §8's Compose-rule convention scoped to the five UI tests only.
- **v2 (2026-08-04) — Gate-2 round 1 applied.** Auditor: Codex `gpt-5.5`, reasoning `high`, via
  `scripts/run-codex.sh` (rule 53), `RUN-CODEX RESULT: SUCCEEDED`. Log:
  `scratchpad/f164-gate2-r1.txt`. Verdict **C=0 H=4 M=8 L=3**. Disposition — every finding FIXED,
  none accepted-as-is:
  - *HIGH* — "base64 GCM covered by the keyed `password`/`api_key` rules" was **false**: the ported
    iOS alternation cannot match this codebase's camelCase `encryptedApiKey` / `encryptedPassword`.
    → new redaction rule + real-shape vectors incl. a serialized-entity dump (§6.1, WI-2).
  - *HIGH ×2* — WI-7 still carried the pre-fix provider strategy (`file_paths.xml` in `writes:`,
    assertions against the **book** authority). → WI-7 rewritten to the separate
    `diagnosticsprovider`, `file_paths.xml` moved to `forbidden_writes`, plus a NEGATIVE test that
    the book authority *rejects* the export file (§6.4 invariant now asserted, not assumed).
  - *HIGH* — WI-8's placeholder write path violated rule 55 (`files_touched ⊆ write-set`).
    → `dispatchable: false` + a written precondition that the plan is revised with the real path
    once #171 lands; runs inline until then.
  - *HIGH* — WI-9's "seed a secret via a 401" could **false-pass**, since the AI clients set auth
    headers but never log them. → unique-nonce fixture per leak shape, plus an assertion that the
    nonce actually entered the capture path so an empty log cannot masquerade as a pass.
  - *MEDIUM* — `FallbackDiagnosticsSource`'s "empty ⇒ fall back" contract flip-flopped and hid ring
    entries behind a sparse logcat. → replaced by `SourceResult` (`Available`/`Unavailable`) +
    `CompositeDiagnosticsSource` that merges and dedupes by a VLog sequence id.
  - *MEDIUM* — export writer took a caller-controlled filename. → filename derived from the
    injected clock; canonical-child assertion.
  - *MEDIUM* — timeout path specified only `destroy()`. → close streams, `destroy()`,
    `destroyForcibly()`, always `waitFor()`; asserted with a fake Process that ignores `destroy()`.
  - *MEDIUM* — `ActivityNotFoundException` criterion was unsatisfiable by an Intent-returning
    function. → separate `shareDiagnostics()` launcher owns that guarantee.
  - *MEDIUM* — WI-6 was ~600 LOC. → split into **WI-6a** (row/chips/footer) and **WI-6b**
    (screen shell + states).
  - *MEDIUM* — rule-24 sync omitted README. → added, and deliberately scheduled with WI-8 so we
    don't document a screen no user can open.
  - *MEDIUM* — `VLog` silently changes logcat tags from per-class to category tags. → made an
    explicit, tested, documented break; original class name preserved in the message body.
  - *LOW ×3* — third WebDAV Basic-auth setter (`WebDavClient.kt:195`) added; §2's conclusion
    reworded to claim only uid-*filtering* (permission left entirely to WI-1); R8/minify criterion
    corrected — the release variant declares no minify config today.
  - **Author-originated (not from the audit)**: §6.4 separate `DiagnosticsFileProvider` (found by
    reading `BookFileProvider.displayNameFor()`, which matches on filename against a *global*
    registry and is not scoped to `books/`); §2 binding go/no-go criterion if WI-1's gate fails;
    §6.5 Android container + degraded-state decisions, which closed two gaps that would otherwise
    have forced an implementer to invent UI.
- **v1 (2026-08-04)** — Gate-1 draft. Feasibility of app-self-read `logcat` **tested live** on
  `emulator-5554` (API 35) rather than assumed (§2), including the cross-uid isolation control and the
  `-v uid` hard-filter defense; the `runas_app`-vs-`untrusted_app` gap is recorded as an open caveat
  that WI-1's connected test closes. Reachability declared against **#171** with WI-8/WI-9 explicitly
  blocked and the row capped at `DONE` (§3). Design read in full; two design-rejected alternatives
  (X2 pinned CTA, X3 error badge) carried into §5.
