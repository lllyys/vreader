# Plugins Reference

## Official Plugins

### Installation Pattern

```bash
# In src-tauri directory
cargo add tauri-plugin-<name>

# In frontend
npm add @tauri-apps/plugin-<name>
```

Register in Rust:

```rust
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_<name>::init())
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

## File System Plugin

**Install:** `cargo add tauri-plugin-fs` + `npm add @tauri-apps/plugin-fs`

### Capabilities Required

```json
{
  "permissions": [
    "fs:default",
    "fs:allow-read-text-file",
    "fs:allow-write-text-file",
    "fs:allow-read-dir",
    {
      "identifier": "fs:scope",
      "allow": [{ "path": "$APPDATA/**" }]
    }
  ]
}
```

### Usage

```typescript
import { 
    readTextFile, 
    writeTextFile, 
    readDir, 
    exists,
    mkdir,
    remove,
    rename,
    BaseDirectory 
} from '@tauri-apps/plugin-fs';

// Read file
const content = await readTextFile('config.json', { 
    baseDir: BaseDirectory.AppConfig 
});

// Write file
await writeTextFile('data.txt', 'Hello World', { 
    baseDir: BaseDirectory.AppData 
});

// Read directory
const entries = await readDir('documents', { 
    baseDir: BaseDirectory.Home 
});

// Check existence
if (await exists('config.json', { baseDir: BaseDirectory.AppConfig })) {
    // file exists
}

// Create directory
await mkdir('my-app-data', { 
    baseDir: BaseDirectory.AppData, 
    recursive: true 
});
```

### Base Directories

| Enum | macOS | Windows | Linux |
|------|-------|---------|-------|
| `AppConfig` | `~/Library/Application Support/{id}` | `%APPDATA%\{id}` | `~/.config/{id}` |
| `AppData` | `~/Library/Application Support/{id}` | `%APPDATA%\{id}` | `~/.local/share/{id}` |
| `AppCache` | `~/Library/Caches/{id}` | `%LOCALAPPDATA%\{id}\cache` | `~/.cache/{id}` |
| `Home` | `~` | `%USERPROFILE%` | `~` |
| `Document` | `~/Documents` | `%USERPROFILE%\Documents` | `~/Documents` |
| `Download` | `~/Downloads` | `%USERPROFILE%\Downloads` | `~/Downloads` |
| `Temp` | `/tmp` | `%TEMP%` | `/tmp` |

## Dialog Plugin

**Install:** `cargo add tauri-plugin-dialog` + `npm add @tauri-apps/plugin-dialog`

### Capabilities

```json
{
  "permissions": ["dialog:default"]
}
```

### File Dialogs

```typescript
import { open, save, ask, message, confirm } from '@tauri-apps/plugin-dialog';

// Open file
const filePath = await open({
    multiple: false,
    directory: false,
    filters: [
        { name: 'Images', extensions: ['png', 'jpg', 'gif'] },
        { name: 'All Files', extensions: ['*'] }
    ],
    defaultPath: '/home/user/Documents',
    title: 'Select a file'
});

// Open multiple files
const filePaths = await open({ multiple: true });

// Open directory
const dirPath = await open({ directory: true });

// Save dialog
const savePath = await save({
    defaultPath: 'document.pdf',
    filters: [{ name: 'PDF', extensions: ['pdf'] }]
});
```

### Message Dialogs

```typescript
// Info message
await message('Operation completed successfully', { 
    title: 'Success',
    kind: 'info'
});

// Error message
await message('Something went wrong', { 
    title: 'Error',
    kind: 'error'
});

// Confirm dialog (Yes/No)
const confirmed = await confirm('Are you sure you want to delete?', {
    title: 'Confirm Delete',
    kind: 'warning'
});

// Ask dialog (custom buttons)
const answer = await ask('Save changes before closing?', {
    title: 'Unsaved Changes',
    kind: 'warning',
    okLabel: 'Save',
    cancelLabel: 'Discard'
});
```

## Clipboard Plugin

**Install:** `cargo add tauri-plugin-clipboard-manager` + `npm add @tauri-apps/plugin-clipboard-manager`

### Capabilities

```json
{
  "permissions": [
    "clipboard-manager:allow-read",
    "clipboard-manager:allow-write",
    "clipboard-manager:allow-write-html",
    "clipboard-manager:allow-read-image",
    "clipboard-manager:allow-write-image"
  ]
}
```

### Usage

```typescript
import { 
    readText, 
    writeText, 
    readImage, 
    writeImage, 
    writeHtml,
    clear 
} from '@tauri-apps/plugin-clipboard-manager';

// Text
await writeText('Hello clipboard');
const text = await readText();

// HTML
await writeHtml('<h1>Rich content</h1>', 'Rich content'); // html, plaintext fallback

// Image (desktop only)
const imageData = await readImage();
const blob = new Blob([await imageData.rgba()], { type: 'image/png' });

// Write image
await writeImage(imageBuffer);

// Clear
await clear();
```

## Store Plugin (Key-Value Storage)

**Install:** `cargo add tauri-plugin-store` + `npm add @tauri-apps/plugin-store`

### Usage

```typescript
import { Store } from '@tauri-apps/plugin-store';

const store = new Store('settings.json');

// Set values
await store.set('theme', 'dark');
await store.set('user', { name: 'John', id: 123 });

// Get values
const theme = await store.get<string>('theme');
const user = await store.get<{ name: string; id: number }>('user');

// Check and delete
if (await store.has('theme')) {
    await store.delete('theme');
}

// List keys
const keys = await store.keys();

// Save to disk (auto-saved on changes, but can force)
await store.save();

// Load from disk
await store.load();

// Clear all
await store.clear();
```

## Shell Plugin

**Install:** `cargo add tauri-plugin-shell` + `npm add @tauri-apps/plugin-shell`

### Capabilities

```json
{
  "permissions": [
    "shell:allow-open",
    "shell:allow-execute",
    {
      "identifier": "shell:allow-execute",
      "allow": [{ "cmd": "node", "args": true }]
    }
  ]
}
```

### Usage

```typescript
import { Command, open } from '@tauri-apps/plugin-shell';

// Open URL in default browser
await open('https://tauri.app');

// Open file with default app
await open('/path/to/document.pdf');

// Execute command
const output = await Command.create('node', ['--version']).execute();
console.log(output.stdout);

// Spawn with streaming output
const command = Command.create('npm', ['install']);
command.on('close', (data) => {
    console.log(`Command finished with code ${data.code}`);
});
command.on('error', (error) => console.error(error));
command.stdout.on('data', (line) => console.log(line));
command.stderr.on('data', (line) => console.error(line));

const child = await command.spawn();
// Later: await child.kill();
```

## Updater Plugin

**Install:** `cargo add tauri-plugin-updater` + `npm add @tauri-apps/plugin-updater`

### Configuration (tauri.conf.json)

```json
{
  "plugins": {
    "updater": {
      "pubkey": "YOUR_PUBLIC_KEY_HERE",
      "endpoints": [
        "https://releases.myapp.com/{{target}}/{{arch}}/{{current_version}}"
      ],
      "windows": {
        "installMode": "passive"
      }
    }
  }
}
```

### Generate Keys

```bash
npx tauri signer generate -w ~/.tauri/myapp.key
```

### Usage

```typescript
import { check } from '@tauri-apps/plugin-updater';
import { relaunch } from '@tauri-apps/plugin-process';

const update = await check();

if (update?.available) {
    console.log(`Update ${update.version} available`);
    
    await update.downloadAndInstall((progress) => {
        if (progress.event === 'Started') {
            console.log(`Downloading ${progress.data.contentLength} bytes`);
        } else if (progress.event === 'Progress') {
            console.log(`Downloaded ${progress.data.chunkLength} bytes`);
        } else if (progress.event === 'Finished') {
            console.log('Download complete');
        }
    });
    
    await relaunch();
}
```

## Developing Custom Plugins

### Plugin Structure

```
tauri-plugin-myplugin/
├── Cargo.toml
├── src/
│   ├── lib.rs          # Plugin definition
│   ├── commands.rs     # Command handlers
│   └── desktop.rs      # Desktop implementation
├── permissions/
│   ├── default.toml    # Default permissions
│   └── autogenerated/
├── guest-js/           # Frontend bindings
│   └── index.ts
└── package.json
```

### Basic Plugin (Rust)

```rust
// src/lib.rs
use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime, Manager,
};

mod commands;

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("myplugin")
        .invoke_handler(tauri::generate_handler![
            commands::my_command,
        ])
        .setup(|app, api| {
            // Plugin setup
            Ok(())
        })
        .build()
}

// src/commands.rs
#[tauri::command]
pub fn my_command(value: String) -> String {
    format!("Received: {}", value)
}
```

### Frontend Bindings

```typescript
// guest-js/index.ts
import { invoke } from '@tauri-apps/api/core';

export async function myCommand(value: string): Promise<string> {
    return invoke('plugin:myplugin|my_command', { value });
}
```

### Using the Plugin

```rust
// In app
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_myplugin::init())
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

### Plugin Permissions

```toml
# permissions/default.toml
[default]
description = "Default permissions for myplugin"
permissions = ["allow-my-command"]

[[permission]]
identifier = "allow-my-command"
description = "Allows calling my_command"
commands.allow = ["my_command"]
```
