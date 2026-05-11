// clickat.swift — single tap at mac-space (x, y) via CGEventPost.
//
// Usage: swift clickat.swift <x> <y>
//
// Posts leftMouseDown → 50ms → leftMouseUp at the given mac-space
// coordinates. The iOS Simulator translates this to a single iOS touch
// at the corresponding sim-space point (CoreSimulator handles the
// coordinate mapping). Works for buttons, toggles, segmented controls,
// list rows, picker selections, sheet Done buttons, context-menu items.
//
// Coordinates come from `osascript … System Events → process "Simulator"
// → position` queries (mac-space). Use the AX-tree element's
// (position.x + size.width/2, position.y + size.height/2) for the click
// center.

import Foundation
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
    FileHandle.standardError.write("usage: swift clickat.swift <x> <y>\n".data(using: .utf8)!)
    exit(1)
}
let point = CGPoint(x: x, y: y)
let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
down?.post(tap: .cghidEventTap)
usleep(50_000)
up?.post(tap: .cghidEventTap)
print("clicked at \(x),\(y)")
