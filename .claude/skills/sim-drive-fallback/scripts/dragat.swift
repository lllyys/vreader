// dragat.swift — drag from (x1, y1) to (x2, y2) via CGEventPost.
//
// Usage: swift dragat.swift <x1> <y1> <x2> <y2>
//
// Posts mouseMoved → leftMouseDown → 10 intermediate mouseDragged
// events spaced 20ms apart → leftMouseUp. The intermediate moves are
// what makes iOS interpret this as a scroll/drag rather than a tap
// with a long path — without them, the simulator's gesture recognizer
// quantizes the motion to a single touch event.
//
// Works for:
//   - SwiftUI .sheet content scroll (Reading Settings, Filter, etc.)
//   - Sheet grabber expand (drag the grabber upward)
//   - Library scroll, list view scroll
//
// Does NOT work for:
//   - WKWebView touch-drag (EPUB content scroll, Foliate page advance,
//     EPUB rubber-band overscroll). Mouse drag isn't routed into the
//     web view's touch handler — only native UIScrollView gestures
//     respond.
//
// Coordinate space is mac-space, same as clickat.swift.

import Cocoa
import CoreGraphics

guard CommandLine.arguments.count >= 5,
      let x1 = Double(CommandLine.arguments[1]),
      let y1 = Double(CommandLine.arguments[2]),
      let x2 = Double(CommandLine.arguments[3]),
      let y2 = Double(CommandLine.arguments[4]) else {
    FileHandle.standardError.write("usage: swift dragat.swift <x1> <y1> <x2> <y2>\n".data(using: .utf8)!)
    exit(2)
}

let p1 = CGPoint(x: x1, y: y1)
let p2 = CGPoint(x: x2, y: y2)

let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p1, mouseButton: .left)
move?.post(tap: .cghidEventTap)
usleep(50_000)

let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p1, mouseButton: .left)
down?.post(tap: .cghidEventTap)
usleep(50_000)

let steps = 10
for i in 1...steps {
    let t = Double(i) / Double(steps)
    let x = x1 + (x2 - x1) * t
    let y = y1 + (y2 - y1) * t
    let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
    drag?.post(tap: .cghidEventTap)
    usleep(20_000)
}

let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p2, mouseButton: .left)
up?.post(tap: .cghidEventTap)
print("dragged \(x1),\(y1) → \(x2),\(y2)")
