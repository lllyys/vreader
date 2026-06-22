# Feature #118 — Android AI provider + chat/summary

**Status:** Gate 1 (plan). Part of the #110 Android Phase-3 parity driver. Implements the
"VReader AI Provider & Chat" canvas (`dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx`
`AiProviderList` + `AiChatPanel`, + the committed `EditorSheet` provider editor). Design landed
(needs-design #1798 closed). **Bilingual interlinear (the canvas's part B) is a SEPARATE follow-on
feature** (#119) — it's tied to the reader rendering and is the heavier integration; this feature is
the provider gate + chat/summary (the canvas's parts A + C).

## Problem

iOS has AI chat (#89) + a configurable AI provider (#50/#79); Android has neither. One
user-configured provider credential drives chat + summaries (and, later, bilingual). Android needs:
the provider config + storage, the AI client (OpenAI-compatible + Anthropic, streaming), and the
designed provider-list / editor / chat-panel UI.

## Surface area (all new, under `android/app/.../ai/`)

- **`AiProviderKind.kt`** — `enum { openAiCompatible, anthropic }` with `defaultBaseUrl` /
  `defaultModel` / `displayName` / `endpointPathHint` (mirrors iOS `ProviderKind`:
  openai→`https://api.openai.com/v1`·`gpt-4o-mini`·appends `/chat/completions`;
  anthropic→`https://api.anthropic.com`·`claude-sonnet-4-6`·appends `/v1/messages`).
- **`AiProviderProfile.kt`** — `(id, name, kind, baseUrl, model, temperature=0.7, maxTokens=2048)`;
  the API key is kept ONLY as a `SecretCipher` token (the #116 `KeystoreSecretCipher`).
- **`AiProviderStore.kt`** — DataStore JSON list of profiles + the active id; API key via
  `SecretCipher`. CRUD + `activeProfile()` + `apiKey(id)`. **Reuses the #116 `WebDavServerStore`
  pattern verbatim** (this is the proven shape).
- **`AiClient.kt`** — `interface AiClient { fun streamChat(req): Flow<AiChunk>; suspend fun chat(req): AiResponse; suspend fun testConnection(): TestResult }`.
  `AiRequest(messages, model, temperature, maxTokens, system?)`, `AiMessage(role, content)`,
  `AiChunk(deltaText)`, `AiResponse(text)`, typed `AiError` (auth401/rateLimited429/offline/
  timeout/http/decode). Mirrors iOS `AIProvider`.
- **`OpenAiCompatibleProvider.kt`** / **`AnthropicProvider.kt`** — `HttpURLConnection` (the #116
  transport precedent): POST chat with the kind's path + auth header (Bearer vs `x-api-key` +
  `anthropic-version`), **SSE streaming parsed into a `Flow<AiChunk>`** (handle `data:` lines, the
  `[DONE]` sentinel, partial JSON), one-shot non-stream for summaries/test. JSON via kotlinx.
- **`AiProviderFactory.kt`** — `(profile, apiKey) -> AiClient` by kind.
- **UI (Compose, per the imported design):**
  - `AiProviderListScreen` — the gate (`AiProviderList`): unconfigured onboard → Add; configured
    list with active radio + per-provider status (model / rejection reason); tap → editor.
  - `ProviderEditSheet` — the committed `EditorSheet` contract: Provider Type segmented · Name ·
    Endpoint (Base URL + Model, blank→default) · Sampling (Temperature slider + Max Tokens stepper)
    · API Key (secure) · Connection (Test — enabled once a key is entered, states testing/ok/fail).
  - `AiChatPanel` — chat + summary over a dimmed reader: unconfigured gate / idle (suggested
    prompts) / in-flight (typing) / answer (streams in the reading serif) / summary (cached
    key-points + regenerate). Markdown rendered via the #112 `MarkdownRenderer`.
  - A `BackupTokens`-style `AiTokens` (light+dark) from the design's `UI` map, or reuse the
    existing token set if present.
- **`AiChatViewModel.kt`** — `StateFlow<AiChatUiState>`; drives streamChat; per-chapter summary
  cache (in-memory v1).

### Files OUT of scope (this feature)

Bilingual interlinear reader + setup sheet (→ #119). Chat session persistence / history (v1 =
in-memory single session). Tool/function-calling (iOS #91). RAG/citations. A production Settings
entry is wired (the provider list is reachable) but bilingual is not.

## Prior art / precedent

- iOS `ProviderKind` / `AIProvider` / `OpenAICompatibleProvider` / `AnthropicProvider` / `AIChatViewModel`.
- #116 `WebDavServerStore` + `KeystoreSecretCipher` (the provider-store + credential pattern — reuse).
- #116 `WebDavClient` (HttpURLConnection transport + typed errors + bounded reads).
- #112 `MarkdownRenderer` (render the AI's markdown answer).
- #114 backup Compose surfaces (the `BackupScaffold`/`AppSheet`/token vocabulary the design reuses).

## Work items

| WI | Scope | Tier |
| --- | --- | --- |
| WI-1 | `AiProviderKind` + `AiProviderProfile` + `AiProviderStore` (DataStore + `SecretCipher`). JVM tests (reuses the WebDavServerStore shape). | foundational |
| WI-2 | `AiClient` interface + DTOs + `OpenAiCompatibleProvider` + `AnthropicProvider` (HTTP + SSE-stream→Flow) + `testConnection` + factory. JVM tests (ServerSocket SSE fake). | foundational |
| WI-3 | `AiProviderListScreen` + `ProviderEditSheet` (the `EditorSheet` contract) + test-connection wired, per the design. Instrumented Compose tests. | behavioral |
| WI-4 | `AiChatPanel` + `AiChatViewModel` (streaming answer, suggested prompts, summary cache, unconfigured gate), per the design. Instrumented Compose tests. | behavioral |
| WI-5 | Integration + acceptance: chat + test-connection end-to-end against a LIVE local mock-SSE provider on the emulator (a `run-ai-roundtrip.sh` serving an OpenAI-compatible SSE stub). Evidence file → feature VERIFIED. | behavioral (final) |

## Test catalogue

- `AiProviderStoreTest` (Robolectric/JVM): CRUD, active-id, password-as-cipher-token, keep-existing-key.
- `AiProviderKindTest`: defaults/path-hint per kind.
- `OpenAiCompatibleProviderTest` / `AnthropicProviderTest` (JVM, ServerSocket SSE fake): stream
  parse (`data:` deltas, `[DONE]`, partial JSON), one-shot, auth401/429/offline mapping, the
  endpoint path append (no doubled `/chat/completions`).
- `AiChatViewModelTest` (Robolectric): unconfigured gate, send→stream→answer, summary cache hit.
- Compose: `AiProviderListScreenTest`, `ProviderEditSheetTest`, `AiChatPanelTest` (states).
- `AiRoundTripConnectedTest` (androidTest): live local SSE stub → configure provider → test-connection
  ok → send a prompt → streamed answer assembled.

## Risks + mitigations

- **SSE parsing** is the correctness core — `data:` framing, `[DONE]`, partial lines across reads,
  Anthropic's event-typed SSE (`content_block_delta`) vs OpenAI's `choices[].delta.content`.
  Mitigation: per-provider parser + a ServerSocket SSE fake covering partial frames.
- **Credential at rest** — reuse `KeystoreSecretCipher` (already on-device verified in #116).
- **Untrusted provider responses** — bounded reads (the #117 lesson); never trust `Content-Length`.
- **No provider configured** — every AI surface gates to the provider list (the design's spine).

## Backward compat

Purely additive (new package; no entity/schema change). A new Settings entry reaches the provider
list; nothing to migrate.

## Acceptance criteria

1. Provider config persists (DataStore + Keystore); the API key is never stored in plaintext.
2. `OpenAiCompatibleProvider` + `AnthropicProvider` stream a chat completion (SSE→Flow) and do a
   one-shot + test-connection, with typed errors — JVM.
3. The provider list + editor (per the committed design) configure/test a provider — Compose.
4. The chat panel streams an answer in the reading serif + renders a cached chapter summary, and
   gates to the provider list when unconfigured — Compose.
5. **Connected**: against a live local OpenAI-compatible SSE stub on the emulator, test-connection
   succeeds and a sent prompt streams an assembled answer. Evidence file.

## Audit fixes applied (Gate-2, Codex)

- **(High) `#112 MarkdownRenderer` is a single-line TXT/MD chunk renderer, not a chat renderer** →
  WI-4 adds an `AiMarkdownRenderer` (a block/line wrapper over the markdown primitives) with tests
  for multi-line headings/bullets/code spans, partial-streaming markdown, CJK, and empty input. Do
  NOT cite `MarkdownRenderer` as directly sufficient.
- **(Medium) "reuse WebDavServerStore verbatim" overstated** → reword to "reuse the DataStore +
  `SecretCipher` credential pattern". `AiProviderStore` adds: `activeId`, `loadSnapshot()` (profiles
  + activeId atomically), active-deletion behavior (deleting the active profile clears/reselects
  activeId), and **request-start snapshot semantics** (a chat/test reads one consistent profile
  snapshot, not live store reads mid-request).
- **(Medium) shared SSE framing under-specified** → add a shared bounded **`SseEventReader`** that
  emits COMPLETE SSE events: blank-line event boundaries, `:`-comment/keepalive lines skipped,
  multiple `data:` lines per event concatenated, EOF-before-sentinel handled, cancellation
  disconnects the `HttpURLConnection`. Per-provider PAYLOAD parsers consume its events: OpenAI
  `choices[].delta.content` + `[DONE]`; Anthropic `type=content_block_delta`/`delta.text`,
  `message_stop`, and `error`.
- **(Medium) streaming is unbounded** → caps: `MAX_LINE_BYTES` (64KB), `MAX_EVENT_BYTES` (256KB),
  `MAX_ANSWER_CHARS` (~200K), `MAX_ERROR_BODY` (64KB), read/socket timeout, and a cancel path that
  disconnects. Tests: oversized line/event + endless-keepalive → typed error / bounded stop.
- **(Medium) summary cache key** → key = `bookFingerprintKey + chapterId + sourceTextDigest +
  providerId + model + promptVersion`; invalidate on provider/model change and on explicit
  Regenerate. (In-memory v1; the key makes it correct, not just fast.)
- **(Medium) edit-mode blank key** → a NEW profile requires an entered key (Test + Save). An EDIT
  with a blank secure field uses the EXISTING decrypted key for Test/Save; entering a new key
  replaces it. **The key + the `Authorization`/`x-api-key` header are NEVER logged.**
- **(Low) enum parity** → `AiProviderKind { openAiCompatible, anthropicNative }` (matches iOS
  `ProviderKind` raw values for future config parity).
- **(Low) WI-5 also exercises Anthropic** → keep OpenAI-compatible for the emulator acceptance, AND
  add an Anthropic acceptance-grade JVM SSE fake (`content_block_delta` / `message_stop` / `error` /
  premature-EOF).
- **(Low) #119 bilingual stays separate** → #118 exposes the active-provider + `AiClient` seams
  #119 will consume; no bilingual UI/reader integration here.
- **(Low) WI-2 internal sequence** → contracts/errors → shared HTTP request construction → shared
  `SseEventReader` → OpenAI parser → Anthropic parser → factory/`testConnection`.

## Revision history

- **v1** (2026-06-22) — Gate-1 draft.
- **v2** (2026-06-22) — Gate-2 Codex audit (1 High + 5 Medium + 4 Low), all folded in above. No
  redesign; HttpURLConnection-for-SSE + the bilingual #119 split + the 5-WI shape confirmed.
