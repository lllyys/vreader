// pastekey.swift — send cmd+V to whatever is currently focused.
//
// Usage: swift pastekey.swift
//
// Posts cmd-down → V-down → 50ms → V-up → cmd-up via CGEventPost.
// The Mac clipboard is shared with the iOS Simulator, so:
//
//   osascript -e 'set the clipboard to "the text"'
//   swift clickat.swift <field_x> <field_y>   # focus the TextField
//   swift pastekey.swift                      # paste
//
// Works in SwiftUI `TextField`. Does NOT work reliably in SecureField
// — that view swallows synthetic cmd+V on some iOS versions.
//
// Why CGEvent rather than `xcrun simctl io booted type` — that
// command doesn't exist; `simctl` has no text-entry primitive. The
// only headless paths are the AX inspector (not scriptable) or the
// shared clipboard + paste combo. This skill picks the latter.

import Cocoa
import CoreGraphics

let src = CGEventSource(stateID: .hidSystemState)

// macOS virtual keycodes: Command = 0x37, V = 0x09.
let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
cmdDown?.flags = .maskCommand
cmdDown?.post(tap: .cghidEventTap)

let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
vDown?.flags = .maskCommand
vDown?.post(tap: .cghidEventTap)
usleep(50_000)

let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
vUp?.flags = .maskCommand
vUp?.post(tap: .cghidEventTap)

let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
cmdUp?.post(tap: .cghidEventTap)

print("cmd+V sent")
