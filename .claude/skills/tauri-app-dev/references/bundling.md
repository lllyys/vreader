# Bundling and Distribution Reference

## Build Commands

```bash
# Development (hot reload)
npm run tauri dev

# Production build (all targets)
npm run tauri build

# Specific bundle types
npm run tauri build -- --bundles deb,appimage    # Linux
npm run tauri build -- --bundles nsis,msi        # Windows
npm run tauri build -- --bundles app,dmg         # macOS

# Debug build (larger, with debug symbols)
npm run tauri build -- --debug

# Specific target architecture
npm run tauri build -- --target x86_64-pc-windows-msvc
npm run tauri build -- --target aarch64-apple-darwin
npm run tauri build -- --target x86_64-unknown-linux-gnu
```

## Output Locations

```
target/release/bundle/
├── macos/
│   ├── MyApp.app/            # Application bundle
│   └── MyApp.app.tar.gz      # Compressed (for updater)
├── dmg/
│   └── MyApp_0.1.0_x64.dmg   # Disk image
├── nsis/
│   └── MyApp_0.1.0_x64-setup.exe  # Windows installer
├── msi/
│   └── MyApp_0.1.0_x64_en-US.msi  # MSI installer
├── deb/
│   └── my-app_0.1.0_amd64.deb     # Debian package
├── appimage/
│   └── my-app_0.1.0_amd64.AppImage # Portable Linux
└── rpm/
    └── my-app-0.1.0-1.x86_64.rpm   # RPM package
```

## Configuration (tauri.conf.json)

### Basic Bundle Config

```json
{
  "version": "0.1.0",
  "identifier": "com.mycompany.myapp",
  "productName": "My App",
  "bundle": {
    "active": true,
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ],
    "targets": "all",
    "category": "Productivity",
    "shortDescription": "A great app",
    "longDescription": "A longer description of my app",
    "copyright": "© 2024 My Company",
    "publisher": "My Company"
  }
}
```

### macOS Configuration

```json
{
  "bundle": {
    "macOS": {
      "entitlements": null,
      "exceptionDomain": null,
      "frameworks": [],
      "minimumSystemVersion": "10.13",
      "signingIdentity": null,
      "providerShortName": null
    }
  }
}
```

### Windows Configuration

```json
{
  "bundle": {
    "windows": {
      "certificateThumbprint": null,
      "digestAlgorithm": "sha256",
      "timestampUrl": "http://timestamp.digicert.com",
      "webviewInstallMode": {
        "type": "downloadBootstrapper"
      },
      "nsis": {
        "installerIcon": "icons/icon.ico",
        "headerImage": "icons/header.bmp",
        "sidebarImage": "icons/sidebar.bmp",
        "license": "LICENSE.txt",
        "installMode": "currentUser",
        "languages": ["English"]
      }
    }
  }
}
```

### Linux Configuration

```json
{
  "bundle": {
    "linux": {
      "deb": {
        "depends": ["libwebkit2gtk-4.1-0", "libgtk-3-0"],
        "files": {},
        "section": "utils"
      },
      "rpm": {
        "depends": [],
        "release": "1"
      },
      "appimage": {
        "bundleMediaFramework": false
      }
    }
  }
}
```

## Code Signing

### macOS

1. **Get certificates** from Apple Developer Program
2. **Set environment variables:**
   ```bash
   export APPLE_CERTIFICATE="Developer ID Application: Your Name (TEAMID)"
   export APPLE_CERTIFICATE_PASSWORD="certificate_password"
   export APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
   export APPLE_ID="your@email.com"
   export APPLE_PASSWORD="app-specific-password"
   export APPLE_TEAM_ID="TEAMID"
   ```
3. **Configure in tauri.conf.json:**
   ```json
   {
     "bundle": {
       "macOS": {
         "signingIdentity": "-"
       }
     }
   }
   ```

### Windows

1. **Get code signing certificate** (EV or OV)
2. **Set environment variables:**
   ```bash
   export TAURI_SIGNING_PRIVATE_KEY="path/to/key.pfx"
   export TAURI_SIGNING_PRIVATE_KEY_PASSWORD="password"
   ```
3. **Or configure thumbprint:**
   ```json
   {
     "bundle": {
       "windows": {
         "certificateThumbprint": "THUMBPRINT_HERE"
       }
     }
   }
   ```

## Universal Binary (macOS)

Build for both Apple Silicon and Intel:

```bash
# Install both targets
rustup target add aarch64-apple-darwin
rustup target add x86_64-apple-darwin

# Build universal binary
npm run tauri build -- --target universal-apple-darwin
```

## Cross-Compilation

### Windows from Linux/macOS

Using `cargo-xwin`:

```bash
# Install
cargo install cargo-xwin

# Add Windows target
rustup target add x86_64-pc-windows-msvc

# Build
npm run tauri build -- --target x86_64-pc-windows-msvc
```

### ARM Linux from x86

```bash
# Install toolchain
sudo apt install gcc-aarch64-linux-gnu

# Add target
rustup target add aarch64-unknown-linux-gnu

# Configure linker (~/.cargo/config.toml)
[target.aarch64-unknown-linux-gnu]
linker = "aarch64-linux-gnu-gcc"

# Build
npm run tauri build -- --target aarch64-unknown-linux-gnu
```

## Auto-Update Setup

### 1. Generate Signing Keys

```bash
npx tauri signer generate -w ~/.tauri/myapp.key
# Save the password securely!
```

### 2. Configure tauri.conf.json

```json
{
  "bundle": {
    "createUpdaterArtifacts": true
  },
  "plugins": {
    "updater": {
      "pubkey": "contents of myapp.key.pub",
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

### 3. Set Build Environment

```bash
export TAURI_SIGNING_PRIVATE_KEY=$(cat ~/.tauri/myapp.key)
export TAURI_SIGNING_PRIVATE_KEY_PASSWORD="your_password"
npm run tauri build
```

### 4. Update Endpoint Response

Your server should return JSON:

```json
{
  "version": "1.0.1",
  "notes": "Bug fixes and improvements",
  "pub_date": "2024-01-15T12:00:00Z",
  "platforms": {
    "darwin-x86_64": {
      "signature": "content of .sig file",
      "url": "https://releases.myapp.com/MyApp_1.0.1_x64.app.tar.gz"
    },
    "darwin-aarch64": {
      "signature": "...",
      "url": "https://releases.myapp.com/MyApp_1.0.1_aarch64.app.tar.gz"
    },
    "linux-x86_64": {
      "signature": "...",
      "url": "https://releases.myapp.com/myapp_1.0.1_amd64.AppImage.tar.gz"
    },
    "windows-x86_64": {
      "signature": "...",
      "url": "https://releases.myapp.com/MyApp_1.0.1_x64-setup.nsis.zip"
    }
  }
}
```

## CI/CD (GitHub Actions)

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: macos-latest
            target: universal-apple-darwin
          - os: windows-latest
            target: x86_64-pc-windows-msvc
          - os: ubuntu-22.04
            target: x86_64-unknown-linux-gnu

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 20
          
      - name: Setup Rust
        uses: dtolnay/rust-toolchain@stable
        
      - name: Install dependencies (Linux)
        if: matrix.os == 'ubuntu-22.04'
        run: |
          sudo apt-get update
          sudo apt-get install -y libwebkit2gtk-4.1-dev libappindicator3-dev librsvg2-dev
          
      - name: Install frontend dependencies
        run: npm ci
        
      - name: Build
        env:
          TAURI_SIGNING_PRIVATE_KEY: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY }}
          TAURI_SIGNING_PRIVATE_KEY_PASSWORD: ${{ secrets.TAURI_SIGNING_PRIVATE_KEY_PASSWORD }}
        run: npm run tauri build -- --target ${{ matrix.target }}
        
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: binaries-${{ matrix.os }}
          path: |
            target/*/release/bundle/**/*.dmg
            target/*/release/bundle/**/*.app.tar.gz
            target/*/release/bundle/**/*.exe
            target/*/release/bundle/**/*.msi
            target/*/release/bundle/**/*.deb
            target/*/release/bundle/**/*.AppImage
```

## Bundle Size Optimization

1. **Strip symbols** (automatic in release builds)
2. **Enable LTO** in Cargo.toml:
   ```toml
   [profile.release]
   lto = true
   codegen-units = 1
   ```
3. **Minimize frontend bundle** (tree shaking, minification)
4. **Use `opt-level = "z"`** for size over speed:
   ```toml
   [profile.release]
   opt-level = "z"
   ```
5. **Audit dependencies** - Remove unused crates
