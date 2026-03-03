# Commands and IPC Reference

## Command Definition Patterns

### Basic Command

```rust
#[tauri::command]
fn simple_command() {
    println!("Called from frontend");
}
```

### With Arguments

```rust
#[tauri::command]
fn with_args(name: String, count: i32) -> String {
    format!("{} repeated {} times", name, count)
}
```

### With Result (Error Handling)

```rust
use serde::Serialize;

#[derive(Debug, Serialize)]
struct CommandError {
    message: String,
    code: i32,
}

#[tauri::command]
fn fallible_command(path: String) -> Result<String, CommandError> {
    std::fs::read_to_string(&path).map_err(|e| CommandError {
        message: e.to_string(),
        code: 1,
    })
}
```

### Async Commands

```rust
#[tauri::command]
async fn async_command() -> Result<String, String> {
    // Non-blocking I/O
    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    Ok("Done".into())
}

// Force sync command to run on thread pool
#[tauri::command(async)]
fn heavy_computation() -> i64 {
    // CPU-intensive work runs off main thread
    (0..1_000_000).sum()
}
```

### Accessing Special Parameters

```rust
use tauri::{AppHandle, State, Window, Manager};

#[tauri::command]
fn with_special_params(
    app: AppHandle,           // Application handle
    window: Window,           // Calling window
    state: State<'_, MyState>, // Managed state
) -> String {
    let label = window.label();
    format!("Called from window: {}", label)
}
```

### Rename Arguments

```rust
// Use snake_case in JS instead of camelCase
#[tauri::command(rename_all = "snake_case")]
fn snake_case_args(user_name: String, user_id: i32) {
    // Called with: invoke('snake_case_args', { user_name: 'x', user_id: 1 })
}
```

## Registering Commands

```rust
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            command_a,
            command_b,
            command_c,
        ])
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

**Note:** Only one `invoke_handler` call is used. List all commands in a single `generate_handler!` macro.

## Frontend Invocation

### Basic Call

```typescript
import { invoke } from '@tauri-apps/api/core';

// Simple call
await invoke('simple_command');

// With arguments
const result = await invoke<string>('with_args', { 
    name: 'hello', 
    count: 3 
});

// Error handling
try {
    const data = await invoke<string>('fallible_command', { path: '/etc/hosts' });
} catch (error) {
    console.error('Command failed:', error);
}
```

### With Raw Payload (Binary Data)

```typescript
const buffer = new Uint8Array([1, 2, 3, 4]);
const response = await invoke('process_binary', buffer, {
    headers: { 'Content-Type': 'application/octet-stream' }
});
```

Rust side:

```rust
use tauri::ipc::Request;

#[tauri::command]
fn process_binary(request: Request<'_>) -> Vec<u8> {
    let body = request.body();
    // Process binary data
    body.to_vec()
}
```

## Event System

### Emit from Rust (Global)

```rust
use tauri::Emitter;

#[tauri::command]
fn emit_event(app: AppHandle) {
    app.emit("my-event", "payload data").unwrap();
}
```

### Emit to Specific Window

```rust
use tauri::Emitter;

#[tauri::command]
fn emit_to_window(app: AppHandle) {
    app.emit_to("main", "window-event", serde_json::json!({
        "key": "value"
    })).unwrap();
}
```

### Listen in Frontend

```typescript
import { listen, once } from '@tauri-apps/api/event';

// Persistent listener
const unlisten = await listen<string>('my-event', (event) => {
    console.log('Received:', event.payload);
});

// Later: unlisten();

// One-time listener
await once<string>('my-event', (event) => {
    console.log('Received once:', event.payload);
});
```

### Listen in Rust

```rust
use tauri::Listener;

fn setup_listeners(app: &AppHandle) {
    app.listen("frontend-event", |event| {
        println!("Received: {:?}", event.payload());
    });
}
```

### Emit from Frontend

```typescript
import { emit, emitTo } from '@tauri-apps/api/event';

// Global emit
await emit('frontend-event', { data: 'from frontend' });

// To specific window
await emitTo('settings', 'settings-event', { theme: 'dark' });
```

## Channels (Streaming Data)

For high-throughput streaming (download progress, logs, etc.):

### Rust Side

```rust
use tauri::ipc::Channel;
use serde::Serialize;

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase", tag = "event", content = "data")]
enum ProgressEvent {
    Started { total: u64 },
    Progress { current: u64, total: u64 },
    Finished,
}

#[tauri::command]
async fn download_file(url: String, on_progress: Channel<ProgressEvent>) -> Result<(), String> {
    on_progress.send(ProgressEvent::Started { total: 1000 }).unwrap();
    
    for i in 0..=100 {
        on_progress.send(ProgressEvent::Progress { 
            current: i * 10, 
            total: 1000 
        }).unwrap();
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }
    
    on_progress.send(ProgressEvent::Finished).unwrap();
    Ok(())
}
```

### Frontend Side

```typescript
import { invoke, Channel } from '@tauri-apps/api/core';

const onProgress = new Channel<ProgressEvent>();
onProgress.onmessage = (event) => {
    switch (event.event) {
        case 'Started':
            console.log(`Starting download, total: ${event.data.total}`);
            break;
        case 'Progress':
            console.log(`Progress: ${event.data.current}/${event.data.total}`);
            break;
        case 'Finished':
            console.log('Download complete');
            break;
    }
};

await invoke('download_file', { url: 'https://example.com/file', onProgress });
```

## Response Optimization (Large Data)

For large binary responses, avoid JSON serialization:

```rust
use tauri::ipc::Response;

#[tauri::command]
fn get_large_file() -> Response {
    let bytes = std::fs::read("/path/to/large/file").unwrap();
    Response::new(bytes)
}
```

Frontend receives as `ArrayBuffer`:

```typescript
const buffer: ArrayBuffer = await invoke('get_large_file');
```

## Best Practices

1. **Keep commands focused** - One task per command
2. **Use async for I/O** - Prevents blocking main thread
3. **Return Result for fallible operations** - Proper error handling
4. **Use channels for streaming** - Better than repeated events for high-frequency updates
5. **Validate inputs in Rust** - Don't trust frontend data
6. **Use State for shared data** - Avoid global mutable state
7. **Clean up listeners** - Call `unlisten()` when components unmount
