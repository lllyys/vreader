# Common App Patterns

## Editor Application Pattern

### Document State Management

```rust
use std::sync::Mutex;
use std::path::PathBuf;

struct DocumentState {
    current_file: Mutex<Option<PathBuf>>,
    is_dirty: Mutex<bool>,
    content: Mutex<String>,
}

#[tauri::command]
fn new_document(state: tauri::State<'_, DocumentState>) {
    *state.current_file.lock().unwrap() = None;
    *state.is_dirty.lock().unwrap() = false;
    *state.content.lock().unwrap() = String::new();
}

#[tauri::command]
fn mark_dirty(state: tauri::State<'_, DocumentState>) {
    *state.is_dirty.lock().unwrap() = true;
}

#[tauri::command]
fn is_dirty(state: tauri::State<'_, DocumentState>) -> bool {
    *state.is_dirty.lock().unwrap()
}

#[tauri::command]
fn get_current_file(state: tauri::State<'_, DocumentState>) -> Option<String> {
    state.current_file.lock().unwrap().as_ref().map(|p| p.to_string_lossy().to_string())
}
```

### File Operations with Confirmation

```typescript
import { open, save, ask } from '@tauri-apps/plugin-dialog';
import { readTextFile, writeTextFile } from '@tauri-apps/plugin-fs';
import { invoke } from '@tauri-apps/api/core';

async function confirmSaveChanges(): Promise<boolean> {
    const dirty = await invoke<boolean>('is_dirty');
    if (!dirty) return true;
    
    return await ask('You have unsaved changes. Save before continuing?', {
        title: 'Unsaved Changes',
        kind: 'warning',
        okLabel: 'Save',
        cancelLabel: 'Discard'
    });
}

async function openFile() {
    if (await confirmSaveChanges()) {
        await saveFile();
    }
    
    const path = await open({
        filters: [{ name: 'Markdown', extensions: ['md', 'markdown'] }]
    });
    
    if (path && typeof path === 'string') {
        const content = await readTextFile(path);
        await invoke('set_current_file', { path });
        await invoke('set_content', { content });
        return content;
    }
    return null;
}

async function saveFile(): Promise<boolean> {
    let path = await invoke<string | null>('get_current_file');
    
    if (!path) {
        path = await save({
            filters: [{ name: 'Markdown', extensions: ['md'] }],
            defaultPath: 'untitled.md'
        });
    }
    
    if (path) {
        const content = await invoke<string>('get_content');
        await writeTextFile(path, content);
        await invoke('set_current_file', { path });
        await invoke('mark_clean');
        return true;
    }
    return false;
}
```

## Native Menu Bar

### Rust Setup

```rust
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem, Submenu},
    Manager,
};

pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let menu = create_menu(app.handle())?;
            app.set_menu(menu)?;
            Ok(())
        })
        .on_menu_event(|app, event| {
            match event.id().as_ref() {
                "new" => app.emit("menu:new", ()).unwrap(),
                "open" => app.emit("menu:open", ()).unwrap(),
                "save" => app.emit("menu:save", ()).unwrap(),
                "save-as" => app.emit("menu:save-as", ()).unwrap(),
                "quit" => std::process::exit(0),
                _ => {}
            }
        })
        .run(tauri::generate_context!())
        .expect("error running app");
}

fn create_menu(app: &tauri::AppHandle) -> Result<Menu<tauri::Wry>, tauri::Error> {
    let file_menu = Submenu::with_items(
        app,
        "File",
        true,
        &[
            &MenuItem::with_id(app, "new", "New", true, Some("CmdOrCtrl+N"))?,
            &MenuItem::with_id(app, "open", "Open...", true, Some("CmdOrCtrl+O"))?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "save", "Save", true, Some("CmdOrCtrl+S"))?,
            &MenuItem::with_id(app, "save-as", "Save As...", true, Some("CmdOrCtrl+Shift+S"))?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "quit", "Quit", true, Some("CmdOrCtrl+Q"))?,
        ],
    )?;

    let edit_menu = Submenu::with_items(
        app,
        "Edit",
        true,
        &[
            &PredefinedMenuItem::undo(app, Some("Undo"))?,
            &PredefinedMenuItem::redo(app, Some("Redo"))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, Some("Cut"))?,
            &PredefinedMenuItem::copy(app, Some("Copy"))?,
            &PredefinedMenuItem::paste(app, Some("Paste"))?,
            &PredefinedMenuItem::select_all(app, Some("Select All"))?,
        ],
    )?;

    Menu::with_items(app, &[&file_menu, &edit_menu])
}
```

### Frontend Listener

```typescript
import { listen } from '@tauri-apps/api/event';

await listen('menu:new', () => newDocument());
await listen('menu:open', () => openFile());
await listen('menu:save', () => saveFile());
await listen('menu:save-as', () => saveFileAs());
```

## System Tray

```rust
use tauri::{
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    menu::{Menu, MenuItem},
    Manager,
};

pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let menu = Menu::with_items(app, &[
                &MenuItem::with_id(app, "show", "Show", true, None::<&str>)?,
                &MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?,
            ])?;

            let tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .tooltip("My App")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            window.show().unwrap();
                            window.set_focus().unwrap();
                        }
                    }
                    "quit" => std::process::exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            window.show().unwrap();
                            window.set_focus().unwrap();
                        }
                    }
                })
                .build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

### Minimize to Tray

```rust
use tauri::Manager;

pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let window = app.get_webview_window("main").unwrap();
            
            // Intercept close to minimize to tray instead
            window.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    // Prevent actual close
                    api.prevent_close();
                    // Hide window instead
                    if let Some(w) = window.get_webview_window("main") {
                        w.hide().unwrap();
                    }
                }
            });
            
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

## Recent Files

```rust
use std::sync::Mutex;
use tauri::Manager;

const MAX_RECENT: usize = 10;

struct RecentFiles(Mutex<Vec<String>>);

#[tauri::command]
fn add_recent_file(path: String, state: tauri::State<'_, RecentFiles>) {
    let mut recent = state.0.lock().unwrap();
    recent.retain(|p| p != &path); // Remove if exists
    recent.insert(0, path);        // Add to front
    recent.truncate(MAX_RECENT);   // Limit size
}

#[tauri::command]
fn get_recent_files(state: tauri::State<'_, RecentFiles>) -> Vec<String> {
    state.0.lock().unwrap().clone()
}

#[tauri::command]
fn clear_recent_files(state: tauri::State<'_, RecentFiles>) {
    state.0.lock().unwrap().clear();
}
```

Persist with Store plugin:

```typescript
import { Store } from '@tauri-apps/plugin-store';

const store = new Store('app-state.json');

async function loadRecentFiles(): Promise<string[]> {
    return (await store.get<string[]>('recentFiles')) ?? [];
}

async function saveRecentFiles(files: string[]) {
    await store.set('recentFiles', files);
    await store.save();
}
```

## Window State Persistence

Use `tauri-plugin-window-state`:

```bash
cargo add tauri-plugin-window-state
npm add @tauri-apps/plugin-window-state
```

```rust
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

## Drag and Drop Files

```typescript
import { listen } from '@tauri-apps/api/event';

// Listen for file drops
await listen<string[]>('tauri://file-drop', (event) => {
    const paths = event.payload;
    console.log('Dropped files:', paths);
    // Handle dropped files
});

// Listen for drag hover
await listen('tauri://file-drop-hover', () => {
    // Show drop indicator
});

// Listen for drag cancel
await listen('tauri://file-drop-cancelled', () => {
    // Hide drop indicator
});
```

## Keyboard Shortcuts (Global)

Using `tauri-plugin-global-shortcut`:

```bash
cargo add tauri-plugin-global-shortcut
npm add @tauri-apps/plugin-global-shortcut
```

```typescript
import { register, unregister } from '@tauri-apps/plugin-global-shortcut';

// Register global shortcut
await register('CommandOrControl+Shift+C', () => {
    console.log('Global shortcut triggered');
});

// Unregister when done
await unregister('CommandOrControl+Shift+C');
```

## Deep Linking / URL Scheme

Configure in tauri.conf.json:

```json
{
  "plugins": {
    "deep-link": {
      "desktop": {
        "schemes": ["myapp"]
      }
    }
  }
}
```

Handle incoming URLs:

```rust
use tauri_plugin_deep_link::DeepLinkExt;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_deep_link::init())
        .setup(|app| {
            app.deep_link().register_all()?;
            
            app.deep_link().on_open_url(|event| {
                println!("Opened with URL: {:?}", event.urls());
            });
            
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

## Single Instance (Prevent Multiple Windows)

Using `tauri-plugin-single-instance`:

```bash
cargo add tauri-plugin-single-instance
```

```rust
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, argv, cwd| {
            // Another instance tried to start
            // Focus existing window
            if let Some(window) = app.get_webview_window("main") {
                window.show().unwrap();
                window.set_focus().unwrap();
            }
            
            // Handle arguments from second instance
            println!("Second instance args: {:?}", argv);
        }))
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

## File Watching

```rust
use tauri_plugin_fs::FsExt;
use notify::{Watcher, RecursiveMode};

#[tauri::command]
async fn watch_file(app: tauri::AppHandle, path: String) -> Result<(), String> {
    let (tx, mut rx) = tokio::sync::mpsc::channel(1);
    
    let mut watcher = notify::recommended_watcher(move |res| {
        let _ = tx.blocking_send(res);
    }).map_err(|e| e.to_string())?;
    
    watcher.watch(path.as_ref(), RecursiveMode::NonRecursive)
        .map_err(|e| e.to_string())?;
    
    // Keep watcher alive and emit events
    tokio::spawn(async move {
        while let Some(event) = rx.recv().await {
            if let Ok(event) = event {
                app.emit("file-changed", &path).ok();
            }
        }
    });
    
    Ok(())
}
```

Or use plugin-fs watch:

```typescript
import { watch } from '@tauri-apps/plugin-fs';

const stopWatching = await watch('/path/to/file', (event) => {
    console.log('File event:', event);
}, { recursive: false });

// Later
stopWatching();
```
