# Remote Server Integration — Design Document

**Work Item**: WI-014 (Feature #16)
**Status**: Design only — implementation deferred to V2
**Date**: 2026-03-14

---

## 1. Problem Statement

VReader is an iOS reading app. Users who work with Claude CLI, manage file directories, or maintain document libraries on remote machines (Mac, Linux server, VPS) have no way to interact with those resources from the iOS app. Specifically:

- **AI relay**: Claude CLI runs on a remote machine (requires a full OS, not iOS). Users want to send prompts from VReader and stream responses back without needing a separate SSH client.
- **Directory management**: Users keep large document libraries on remote machines. They want to browse, open, and manage files from VReader without manual file transfer.
- **Reading remote files**: Users want to open a markdown or text file on a remote server directly in VReader's reader view.

A remote server integration bridges this gap by running a lightweight server process on the remote machine and connecting to it from the iOS app.

---

## 2. Protocol Design

### 2.1 WebSocket vs REST

| Criterion | WebSocket | REST (HTTP) |
|-----------|-----------|-------------|
| Bidirectional streaming | Native — server pushes AI tokens, progress updates | Requires SSE or long-polling (workaround) |
| Connection lifecycle | Persistent — one handshake, low overhead per message | Per-request — new connection each time |
| Heartbeat / disconnect detection | Built-in ping/pong frames | Must implement polling |
| Complexity | Moderate — requires connection state management | Simpler per-request model |
| Mobile background behavior | iOS suspends WebSocket after ~30s in background | Same — HTTP requests also cancelled |
| Firewall friendliness | Runs over port 443 (wss://) — same as HTTPS | Same |

**Recommendation**: WebSocket (WSS) as the primary transport.

Rationale: AI response streaming is the core use case. WebSocket provides native bidirectional streaming without the complexity of SSE reconnection or long-polling. The persistent connection also enables the server to push notifications (e.g., file change events) without client polling.

Fallback: REST endpoints for simple one-shot operations (health check, auth token validation) that do not require streaming.

### 2.2 Message Format

Use JSON-RPC 2.0 over WebSocket frames. This is the same protocol used by LSP and MCP, well-understood by the target audience.

**Request (client to server)**:
```json
{
  "jsonrpc": "2.0",
  "id": "req-001",
  "method": "fs.list",
  "params": {
    "path": "/Users/me/documents",
    "recursive": false
  }
}
```

**Response (server to client)**:
```json
{
  "jsonrpc": "2.0",
  "id": "req-001",
  "result": {
    "entries": [
      { "name": "notes.md", "type": "file", "size": 4096, "modified": "2026-03-14T10:00:00Z" },
      { "name": "books", "type": "directory", "modified": "2026-03-13T08:00:00Z" }
    ]
  }
}
```

**Error**:
```json
{
  "jsonrpc": "2.0",
  "id": "req-001",
  "error": {
    "code": -32001,
    "message": "Permission denied",
    "data": { "path": "/etc/shadow" }
  }
}
```

**Streaming notification (server to client, no `id`)**:
```json
{
  "jsonrpc": "2.0",
  "method": "ai.stream",
  "params": {
    "requestId": "req-005",
    "chunk": "Here is the summary of chapter 3...",
    "done": false
  }
}
```

### 2.3 Connection Lifecycle

```
┌───────────┐                           ┌───────────┐
│  iOS App  │                           │  Server   │
└─────┬─────┘                           └─────┬─────┘
      │                                       │
      │──── WSS handshake (TLS) ─────────────>│
      │<─── 101 Switching Protocols ──────────│
      │                                       │
      │──── auth.login { token: "..." } ─────>│
      │<─── result: { session: "...",         │
      │               serverVersion: "1.0" }──│
      │                                       │
      │<──── ping (every 30s) ────────────────│
      │───── pong ───────────────────────────>│
      │                                       │
      │  ... normal request/response flow ... │
      │                                       │
      │──── close frame ─────────────────────>│
      │<─── close frame ─────────────────────-│
      └───────────────────────────────────────┘
```

**States** (client-side state machine):

| State | Description | Transitions |
|-------|-------------|-------------|
| `disconnected` | No connection | `connect()` -> `connecting` |
| `connecting` | WebSocket handshake in progress | success -> `authenticating`, failure -> `disconnected` |
| `authenticating` | Sent `auth.login`, awaiting response | success -> `connected`, failure -> `disconnected` |
| `connected` | Authenticated, ready for commands | close/error -> `reconnecting` |
| `reconnecting` | Connection lost, auto-retry (exponential backoff, max 5 attempts) | success -> `authenticating`, max retries -> `disconnected` |

**Reconnection policy**: Exponential backoff starting at 1s, doubling to max 16s, up to 5 attempts. Reset backoff on successful connection. Do not auto-reconnect if the user explicitly disconnected or if the server rejected the auth token.

---

## 3. Authentication Flow

### 3.1 Token-Based Authentication

The server generates a one-time setup token that the user enters into the iOS app. This avoids password management and is familiar from VS Code Remote, Jupyter Notebook, etc.

**Server setup (one-time)**:
```bash
vreader-server init
# Generates:
#   - TLS self-signed cert (or Let's Encrypt if domain provided)
#   - Auth token: vr_tok_a1b2c3d4e5f6...
#   - Prints: "Enter this token in VReader iOS app: vr_tok_a1b2c3d4e5f6..."
```

**iOS app setup**:
1. User taps "Add Server" in Settings.
2. Enters: server URL (`wss://myserver.local:9876`) + token.
3. App connects, sends `auth.login` with token.
4. Server validates token, returns session ID + server capabilities.
5. App stores connection details in SwiftData (token in Keychain).

### 3.2 TLS Requirement

All connections MUST use WSS (WebSocket Secure). Plain WS is rejected by the client.

- **Public servers**: Use Let's Encrypt certificates.
- **Local network**: Use self-signed certificates. The app must support certificate pinning — on first connection, the user confirms the server fingerprint (Trust On First Use / TOFU model, similar to SSH).
- **iOS ATS**: App Transport Security requires TLS by default. Self-signed certs require an ATS exception for the specific domain/IP, or certificate pinning via `URLSessionDelegate`.

### 3.3 Token Rotation / Expiry

| Token type | Lifetime | Rotation |
|------------|----------|----------|
| Setup token | Single use | Consumed on first successful login |
| Session token | 24 hours (configurable) | Server issues new session token on each reconnect |
| Refresh token | 30 days | Used to obtain new session token without re-entering setup token |

The refresh token is stored in the iOS Keychain via the existing `KeychainService`. If the refresh token expires, the user must re-enter a new setup token (generated on the server).

---

## 4. Command Taxonomy

### 4.1 Directory Listing

| Method | Params | Response | Notes |
|--------|--------|----------|-------|
| `fs.list` | `path: String`, `recursive: Bool?`, `showHidden: Bool?` | `entries: [Entry]` | Entry: `{name, type, size, modified, permissions}` |
| `fs.tree` | `path: String`, `depth: Int?` | `tree: TreeNode` | Nested structure for sidebar display |
| `fs.stat` | `path: String` | `{type, size, modified, created, permissions}` | Single file metadata |
| `fs.search` | `path: String`, `query: String`, `fileTypes: [String]?` | `matches: [Entry]` | Filename search (not content) |

### 4.2 File Operations

| Method | Params | Response | Notes |
|--------|--------|----------|-------|
| `fs.read` | `path: String`, `encoding: String?` | `{content: String, encoding: String}` | UTF-8 default. Max 10MB |
| `fs.readBinary` | `path: String`, `offset: Int?`, `length: Int?` | `{data: String}` | Base64-encoded. For EPUB/PDF |
| `fs.write` | `path: String`, `content: String` | `{bytesWritten: Int}` | Creates parent dirs if needed |
| `fs.create` | `path: String`, `type: "file" \| "directory"` | `{created: Bool}` | Fails if exists |
| `fs.delete` | `path: String`, `recursive: Bool?` | `{deleted: Bool}` | Requires confirmation flag for directories |
| `fs.rename` | `oldPath: String`, `newPath: String` | `{renamed: Bool}` | Atomic rename |
| `fs.copy` | `srcPath: String`, `destPath: String` | `{copied: Bool}` | Deep copy for directories |

### 4.3 AI Relay

| Method | Params | Response | Notes |
|--------|--------|----------|-------|
| `ai.prompt` | `prompt: String`, `context: String?`, `model: String?`, `stream: Bool?` | `{response: String}` or streaming notifications | Forwards to Claude CLI on server |
| `ai.models` | (none) | `{models: [String]}` | List available models on server |
| `ai.cancel` | `requestId: String` | `{cancelled: Bool}` | Cancel in-progress request |

**Streaming flow** for `ai.prompt` with `stream: true`:
1. Client sends `ai.prompt` request with `id: "req-005"`.
2. Server starts Claude CLI process, pipes stdout.
3. Server sends `ai.stream` notifications with `requestId: "req-005"` and chunks.
4. Final notification has `done: true` and optional `usage` stats.
5. Server sends the JSON-RPC response for `id: "req-005"` with the complete text.

### 4.4 Process Management

| Method | Params | Response | Notes |
|--------|--------|----------|-------|
| `proc.run` | `command: String`, `args: [String]`, `cwd: String?`, `timeout: Int?` | `{exitCode: Int, stdout: String, stderr: String}` | Sandboxed execution |
| `proc.start` | `command: String`, `args: [String]`, `cwd: String?` | `{pid: Int}` | Long-running process, output via notifications |
| `proc.signal` | `pid: Int`, `signal: String` | `{sent: Bool}` | Send signal (SIGTERM, SIGINT) |
| `proc.list` | (none) | `{processes: [{pid, command, started, status}]}` | List server-managed processes |

**Important**: Process execution is heavily restricted by the security sandbox (see Section 5).

---

## 5. Security Considerations

### 5.1 Sandboxed Command Execution

The server runs with a configurable allowlist of commands. By default, only a minimal set is permitted:

```yaml
# server-config.yaml
sandbox:
  allowed_commands:
    - claude       # Claude CLI
    - ls
    - cat
    - head
    - tail
    - wc
    - grep
    - find
  blocked_commands:
    - rm -rf /
    - sudo
    - chmod
    - chown
  max_process_time: 300  # seconds
  max_concurrent: 5
```

Commands not in the allowlist are rejected with error code `-32003 (CommandNotAllowed)`.

### 5.2 Path Traversal Prevention

The server defines one or more "root" directories. All `fs.*` operations are confined to these roots:

```yaml
sandbox:
  allowed_roots:
    - /Users/me/documents
    - /Users/me/projects
```

**Enforcement**:
1. Resolve the requested path to its canonical form (`realpath`).
2. Verify the canonical path starts with one of the allowed roots.
3. Reject with error code `-32002 (PathTraversalDenied)` if outside roots.
4. Symlinks are resolved before checking — a symlink inside an allowed root that points outside is rejected.

### 5.3 Rate Limiting

| Resource | Limit | Window |
|----------|-------|--------|
| `fs.*` operations | 100 requests | per minute |
| `ai.prompt` | 10 requests | per minute |
| `proc.run` | 20 requests | per minute |
| WebSocket messages (total) | 500 messages | per minute |
| File read size | 10 MB | per request |
| File write size | 5 MB | per request |

Exceeded limits return error code `-32004 (RateLimitExceeded)` with a `retryAfter` field in seconds.

### 5.4 Audit Logging

All operations are logged to a structured log file on the server:

```json
{
  "timestamp": "2026-03-14T10:30:00Z",
  "session": "sess_abc123",
  "method": "fs.read",
  "params": { "path": "/Users/me/documents/notes.md" },
  "result": "success",
  "durationMs": 12
}
```

Sensitive data (file contents, AI prompts/responses) is NOT logged by default. Verbose mode logs request/response sizes only.

Log rotation: 7 days or 100MB, whichever comes first.

---

## 6. Data Model

### 6.1 ServerConnection (SwiftData)

```swift
@Model
final class ServerConnection {
    @Attribute(.unique) var id: UUID
    var name: String                    // User-assigned label ("Home Mac", "Work Server")
    var url: String                     // "wss://192.168.1.100:9876"
    var certificateFingerprint: String? // SHA-256 of server cert (TOFU)
    var lastConnectedAt: Date?
    var isDefault: Bool                 // Auto-connect on app launch
    var serverVersion: String?          // Reported by server on auth
    var capabilities: [String]          // ["fs", "ai", "proc"] — server reports supported modules

    // Token stored separately in Keychain via KeychainService
    // Key format: "vreader.server.<id>.refreshToken"

    init(name: String, url: String) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.isDefault = false
        self.capabilities = []
    }
}
```

### 6.2 Persistence Strategy

| Data | Storage | Rationale |
|------|---------|-----------|
| Server URL, name, metadata | SwiftData (`ServerConnection`) | Queryable, syncs with iCloud if enabled |
| Refresh token | Keychain (`KeychainService`) | Secure, survives app reinstall |
| Session token | In-memory only | Short-lived, no persistence needed |
| Certificate fingerprint | SwiftData (on `ServerConnection`) | Needed for TOFU verification on reconnect |
| Connection preferences | `PreferenceStore` (UserDefaults) | Auto-connect, timeout settings |

### 6.3 Multiple Server Support

Users can configure multiple servers. The UI shows a server list in Settings with:
- Server name and URL
- Connection status indicator (green dot = connected, gray = disconnected, red = error)
- Last connected timestamp
- "Set as Default" toggle
- Swipe to delete

Only one server is actively connected at a time. Switching servers disconnects the current one and connects to the new one.

---

## 7. Implementation Phases (V2)

### Phase 1: Connection + Directory Browsing

**Scope**: Establish connection, authenticate, browse directories.

**Deliverables**:
- Server binary (Rust or Node.js — TBD) with WebSocket listener, auth, and `fs.list`/`fs.stat`/`fs.tree`
- `ServerConnection` SwiftData model
- Settings UI: Add/edit/delete servers, enter token
- Connection state machine in `ServerConnectionManager` (actor)
- Remote file browser view (reuse `LibraryView` patterns — grid/list toggle, sort)

**Estimated effort**: L (2-3 weeks)

### Phase 2: File Operations

**Scope**: Read, write, create, delete, rename files on the server.

**Deliverables**:
- `fs.read`, `fs.write`, `fs.create`, `fs.delete`, `fs.rename`, `fs.copy` on server
- Open remote file in VReader's reader view (download to temp, open, sync back on save)
- File conflict detection (modified-since check before write)
- Progress indicators for large file transfers

**Estimated effort**: M (1-2 weeks)

### Phase 3: AI Relay

**Scope**: Forward AI prompts to Claude CLI on the remote server and stream responses back.

**Deliverables**:
- `ai.prompt`, `ai.models`, `ai.cancel` on server
- Claude CLI process management (spawn, pipe stdout/stderr, kill)
- Streaming UI integration (reuse `AIChatView` from WI-011)
- Model selection based on server-reported available models

**Estimated effort**: M (1-2 weeks)

**Optional Phase 4**: Process management (`proc.*` commands) — lower priority, scope TBD.

---

## 8. Open Questions

| # | Question | Options | Default if Undecided |
|---|----------|---------|---------------------|
| Q1 | Should we support VPN / local network discovery? | Manual URL entry only vs. mDNS/Bonjour scan | Manual URL entry only (simpler, works across networks) |
| Q2 | Use mDNS/Bonjour for local server discovery? | Yes (auto-discover `_vreader._tcp` services) vs. No | Yes for local network, but manual entry as primary. Bonjour is native on Apple platforms and zero-config |
| Q3 | Should commands queue when offline? | Offline queue with retry vs. immediate failure | Immediate failure with clear error message. Queueing file writes offline is risky (conflicts). May revisit for read-only operations |
| Q4 | Server implementation language? | Rust (performance, single binary) vs. Node.js (faster iteration, npm ecosystem) | Rust — single binary distribution, no runtime dependency, matches VReader's Tauri backend expertise |
| Q5 | Should remote files be cached locally? | Cache with TTL vs. always fetch vs. user choice | Cache with 5-minute TTL for directory listings. File contents fetched on demand, cached in temp directory until session ends |
| Q6 | How to handle large files (EPUB, PDF)? | Stream in chunks vs. download fully first | Download fully to temp directory, then open. Streaming partial EPUB/PDF is not feasible with current reader architecture |
| Q7 | Should the server support multiple simultaneous clients? | Single client vs. multi-client | Multi-client with session isolation. Each client gets its own session and rate limits. Prevents conflicts when same user connects from iPad and iPhone |
| Q8 | File change watching? | Server pushes `fs.changed` notifications vs. client polls | Server pushes via `fs.watch` subscription for open directories. Reduces polling overhead. Unsubscribe on navigate away |

---

## 9. Error Codes

| Code | Name | Description |
|------|------|-------------|
| -32000 | `ServerError` | Generic server-side error |
| -32001 | `AuthenticationFailed` | Invalid or expired token |
| -32002 | `PathTraversalDenied` | Requested path outside allowed roots |
| -32003 | `CommandNotAllowed` | Command not in sandbox allowlist |
| -32004 | `RateLimitExceeded` | Too many requests (includes `retryAfter`) |
| -32005 | `FileTooLarge` | File exceeds size limit for read/write |
| -32006 | `ProcessTimeout` | Command exceeded max execution time |
| -32007 | `ConflictDetected` | File modified since last read (write conflict) |
| -32600 | `InvalidRequest` | Malformed JSON-RPC |
| -32601 | `MethodNotFound` | Unknown method |
| -32602 | `InvalidParams` | Missing or invalid parameters |

---

## 10. References

- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [RFC 6455 — The WebSocket Protocol](https://www.rfc-editor.org/rfc/rfc6455)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) — similar JSON-RPC-over-transport pattern
- [Tauri IPC](https://v2.tauri.app/develop/calling-rust/) — VReader's desktop app uses a similar command/event pattern
- iOS `URLSessionWebSocketTask` — native WebSocket client API (iOS 13+)
