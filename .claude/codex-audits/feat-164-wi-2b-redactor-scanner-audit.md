---
branch: feat/164-wi-2b-redactor-scanner
threadId: 019fcef0-b770-7e11-b2dd-1264781377ee
rounds: 3
final_verdict: ship-as-is
date: 2026-08-05
---

# Codex Audit Log — Feature #164 WI-2b (DiagnosticsRedactor scanner redesign)

Redesign of the keyed-value half of `DiagnosticsRedactor` from a 13-rule regex
grammar into a hand-written left-to-right scanner with an explicit quote state
machine. This function is the ONLY barrier between a captured Android logcat
entry and a user-initiated share-sheet / clipboard export.

## Scope of audit

- `android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsRedactor.kt`
- `android/app/src/test/kotlin/com/vreader/app/diagnostics/DiagnosticsRedactorTest.kt`

Each round's prompt asked the auditor to **construct** a credential-bearing log
line that survives redaction, rather than to comment generically — that is how
every real defect in this WI (and in the abandoned regex predecessor) was found.
Accepted, documented decisions were listed as out of scope each round so the
auditor spent its budget on new ground: the bare-opaque-secret non-goal, the
deleted entropy heuristic, unredacted book titles/filenames, and the file's
length (~150 of its lines are the security rationale header; the lane's
write-set forbids splitting into a new file).

Runner: `scripts/run-codex.sh` (rule 53). Full transcripts in `.reports/audit-r{1,2,3}.txt`.

## Round 1 — thread `019fcee4-9e81-7a71-b935-a86c8fa16f17` — VERDICT: block-recommended

Two High findings, each with a constructed survivor, and three Mediums.

| # | Severity | Finding | Resolution |
| - | -------- | ------- | ---------- |
| 1 | High | `state={\"password\":\"abc\\\"SUFFIX\"}` leaked `SUFFIX`. A boolean "is the opener escaped" cannot distinguish a structural close (`\"`) from a quote inside the value (`\\\"`), so the scan ended early. | FIXED. `closingQuote()` takes `openRun` — the backslash-run length before the OPENING quote — and closes only on a quote whose preceding run is exactly `openRun`. A longer run is value content; no matching close fails closed to end of line. |
| 2 | High | `state={\\\"password\\\":\\\"TOPSECRET123\\\"}` survived ENTIRELY. The separator run required a backslash run of exactly one before a quote, so a double-serialized dump never reached the assignment check. | FIXED. The separator run consumes a backslash run of ANY length followed by a quote and records its length. |
| 3 | High | `Dump{password=abc},USABLE-SUFFIX` leaked `USABLE-SUFFIX`. A closing bracket followed by `,` was treated as proof the dump ended — but `},SUFFIX` is a legal password character sequence. | FIXED. `closesTheDump()` accepts a trailing `,`/`;` only when `nextKeyFollows()` confirms a real next key/value pair. |
| 4 | Medium | `"(".repeat(n) + "password=" + "x)".repeat(n)` was quadratic: bracket state was an `ArrayDeque` and `contains()` is linear in depth, while the value body never pops. | FIXED. Bracket state is an `IntArray(3)` of counters. Pinned by `linear_deepBracketNestingInAnUnquotedValue` (n=50 000). |
| 5 | Medium | `/storage/<FAT-volume-id>` (an SD-card import failure, carrying the user's own folder names) was redacted only when it arrived as a `file://` URL. | FIXED. `PATH_ROOT_ANY` gained `/storage/XXXX-XXXX`, `/mnt/expand/<uuid>`, `/mnt/media_rw`, `/mnt/runtime/<x>`, `/data/misc_{ce,de}/<n>`, all shape-bounded so prose beginning `/storage/` is not swallowed. |
| 6 | Medium | Unrestricted identifier-suffix matching destroyed real diagnostics: `deauthorization=true`, `compassphrase=enabled`. | PARTIALLY ACCEPTED, then closed in round 2. See below. |

### Finding 6 — the argued half

The word-boundary rule was applied to `authorization` **only**, and the position
was put to the auditor explicitly in round 2 rather than asserted. Rationale:
`authorization` is the one credential word with a real English superstring AND
its class consumes the rest of the line, whereas `dbpassword` / `userpassword` /
`oldSecret` are plausible lowercase third-party field names — for the sole egress
barrier a missed credential costs more than an over-redacted contrived
identifier. Round 2 was asked to disprove this by naming a REAL non-credential
identifier ending in one of the unrestricted words. It did (see below), and that
half was then fixed. Both directions are test-pinned
(`negative_englishSuperstringsOfAuthorizationSurvive`,
`lowercaseCompoundCredentialKeys_areStillRedacted`).

## Round 2 — thread `019fceec-f1d9-7681-82e4-51090a35e324` — VERDICT: follow-up-recommended

All six round-1 fixes independently re-traced and confirmed to hold, including
the `from` bound in `closingQuote()`'s run counter (leading backslashes can only
lengthen a candidate run, so the failure mode is over-redaction, never a leak).
No new credential survivor. Zero Critical/High/Medium.

One **Low**, and it produced the counter-example round 1's rationale had claimed
did not exist: Android package-signing diagnostics and JVM tooling emit
`methodSignature=` / `packageSignature=` / `typeSignature=`, none of which
authenticate anything, and the unrestricted `signature` suffix redacted them.

FIXED in `a8a0a25f`: `signature` moved out of `TOKEN_WORDS` into its own branch,
gated by `SIGNATURE_NON_CREDENTIAL` as a **DENY**-list (via
`qualified(..., allowEmpty = false)`) rather than an allow-list — so an
unrecognised `*signature` still redacts. `sig=`, `X-Amz-Signature=`,
`awsSignature=`, `httpSignature=` and a bare HTTP-Signature `signature=` all
remain covered. Pinned by `negative_nonCredentialSignatureIdentifiersSurvive`.

Adversarial cases the auditor tried and could not break: three-plus
serialization layers; mixed escaped/raw quotes; one quote character "closed" by
the other; CRLF and lone-CR line endings; a newline inside an unquoted SPACED
value; CJK/RTL-adjacent keys; the `Authorization` scheme-skip followed by a tab
or multiple spaces.

## Round 3 — thread `019fcef0-b770-7e11-b2dd-1264781377ee` — VERDICT: ship-as-is

**No findings at Critical, High, Medium or Low.** The auditor re-traced the
`signature` deny-list (confirming `X-Amz-Signature` prefix `X-Amz` matches no
deny qualifier, and that an empty prefix under `allowEmpty = false` correctly
falls through to "credential"), confirmed `a8a0a25f` introduces neither
super-linear behaviour nor new over-redaction, and stated plainly that it could
not construct a credential-bearing input that survives whole or leaves a usable
suffix outside the accepted residuals.

Its closing position: it would ship this as the diagnostics export's sole egress
redaction barrier, provided the documented complementary controls — the `VLog`
seam and the WI-3 raw-`android.util.Log` containment check — remain enforced.

## Mutation discipline (16 mutations, 16 killed, 0 shadowed)

Run against the GREEN implementation in five batches, each chosen so every
mutation had at least one uniquely-attributed named test. No branch was
unkillable — the predecessor lane found two shadowed rules that hid real gaps,
and this pass looked specifically for that shape.

| Mutation | Killed by (uniquely) |
| -------- | -------------------- |
| escaped-quote separator branch disabled | `survivor2_escapedJsonAuthorizationContainer`, `quoted_nestedJsonDumpWithEscapedStructuralQuotes` |
| escape-aware close disabled | `quoted_escapedQuoteInsideValue_doesNotTerminateEarly` |
| `qualified()` always true | `negative_nonCredentialTokenIdentifiersSurvive`, `negative_nonCredentialKeyIdentifiersSurvive` |
| AUTH structural-container requirement dropped | `negative_proseAfterAnAuthSchemeWordSurvives` |
| fail-closed quoting → decline | `survivor3_quotedValueContainingTheOtherQuote`, `quoted_truncatedClosingQuote_failsClosedToEndOfLine`, `oracle_aPartialRedactionIsRejected…` |
| stop at EVERY `,`/`&`/`;` (drop next-key gate) | `survivor4_unquotedValueContainingStructuralCharacters` |
| assignment (`:`/`=`) requirement dropped | `negative_keyWordWithoutAnAssignmentSeparatorSurvives`, `negative_nonCredentialTokenIdentifiersSurvive` |
| separator run capped at `{0,8}` (the regex's width) | `survivor1_arbitrarilyLongSeparatorRunBeforeAScheme` |
| `AUTH_SCHEMES` emptied | `auth_serializedJsonHeader`, `auth_webDavBasicHeader`, `auth_proxyAuthorization` |
| TOKEN whitespace stop removed | `unquoted_signedRedirectUrl`, `unquoted_anthropicXApiKeyHeader`, `unquoted_tokenValueStopsAtWhitespace` |
| next-key delimiter never fires | `unquoted_spacedValueRunsPast…`, `unquoted_serializedEntityDump`, `unquoted_queryStringApiKey`, `unquoted_entityDumpWithPlainAndEncrypted` |
| `closesTheDump()` refinement dropped | `survivor4_unquotedValueContainingStructuralCharacters` |
| bracket-closer stop removed entirely | `auth_bracketedAndPairContainers`, `auth_allLetterAndShortCredentials` |
| `sk-` rule disabled | `shape_bareOpenAiKeyWithNoKeyName`, `shape_cjkAdjacentKeyIsStillRedacted` |
| JWT rule disabled | `shape_bareJwt_isRedacted` |
| URL-userinfo rule disabled | all four `url_*` |
| app-books path rule disabled | `path_appBooksPath…`, `path_fileUrlToAnAppBook…` |
| `file://` rule disabled | `path_genericFileUrl…` |
| `content://` rule disabled | `path_safContentUri…` |
| generic path rule disabled | `path_multiUser…`, `path_legacyDataData…`, `path_sharedStorage…`, `path_directoryNameWithASpace…`, `path_spaceHeuristicResidual…` |

## Can idempotency mask a partial redaction?

Yes — which is why it is not relied on. Survivor 3's pre-fix output
(`password=‹redacted›'BrienNeverClose`) was a FIXED POINT of `redact()`, so the
idempotency assertion could not see it. The oracle therefore adds a **per-suffix
absence** assertion: for every secret, no suffix of length ≥ 4 may survive. That
is the exact shape of a partial redaction. `oracle_idempotencyIsNotACompletenessOracle`
pins the point directly, using the accepted bare-secret non-goal as a witness: a
string that is idempotent under `redact()` and still contains the secret.

The suffix oracle also caught two of my own fixtures whose secrets ended in
`word` — the surviving key name `password` contains it. Those fixtures were
changed rather than the assertion weakened.

## Residuals — stated, not hidden

1. **Bare opaque secret, no key / container / shape** — not redacted. Accepted
   non-goal (a `SecretCipher` token is `base64(iv‖ct)` with no framing; the only
   rule that catches it also swallows every content hash, Room row id and
   `fingerprintKey`). Controls: the `VLog` seam and WI-3's containment check.
2. **An unquoted SPACED value literally containing `, <identifier>=`** is
   truncated there. This is the price of preserving `wifiOnly=true` in every
   `toString()`; no lexical rule separates the two.
3. **An unrecognised `Authorization` scheme** consumes the rest of the line.
4. **A value ending in a backslash, or whose closing quote is many lines later**,
   over-redacts — the safe direction.
5. **A bare `signature=<cert>`** loses that one token; keeping it a credential is
   the safe side, since an HTTP-Signature header spells its credential that way.
6. **Lowercase compound non-credential identifiers** ending in a credential word
   (`compassphrase`) over-redact, deliberately — see finding 6.
