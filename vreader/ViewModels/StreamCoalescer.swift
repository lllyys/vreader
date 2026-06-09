// Purpose: Bug #323 — batch streamed AI-reply deltas so the @Observable chat
// transcript is re-published at a CAPPED rate instead of on every token.
//
// Why: `AIChatViewModel.consumeStream` previously did `messages[index].content
// += chunk.text` per token. Mutating the `@Observable messages` array re-publishes
// the WHOLE array, so SwiftUI re-evaluates + re-lays the ENTIRE transcript on
// EVERY streamed token (cost ≈ history-length × reply-length). Fast providers emit
// hundreds of tokens/sec → the main thread saturates → the app freezes during a
// long reply / on the 2nd+ message. Coalescing collapses N per-token publishes
// into a bounded number of batched publishes.
//
// Design:
// - Pure value type, no clock of its own — the caller injects `now`
//   (uptimeNanoseconds) so the policy is deterministically testable.
// - Flush triggers: the FIRST chunk (first token shows promptly), pending reaching
//   `maxChars` (fast streams batch by size), or `minIntervalNanos` elapsed since the
//   last flush (slow trickles still update without waiting to fill a batch).
// - `drain()` flushes whatever remains at stream end / cancel — nothing is lost.
//
// @coordinates-with: AIChatViewModel+Streaming.swift (consumeStream)

import Foundation

/// Batches streamed text deltas into capped-rate flushes (Bug #323).
struct StreamCoalescer {
    /// Flush once the buffered text reaches this many characters.
    let maxChars: Int
    /// Flush once at least this many nanoseconds have elapsed since the last flush.
    let minIntervalNanos: UInt64

    private var pending: String = ""
    /// `nil` until the first flush — the first accepted chunk always flushes so the
    /// first token is visible immediately.
    private var lastFlushNanos: UInt64?

    init(maxChars: Int = 96, minIntervalNanos: UInt64 = 33_000_000) {
        self.maxChars = max(1, maxChars)
        self.minIntervalNanos = minIntervalNanos
    }

    /// Accept a streamed delta. Returns the text to publish if a flush is due now,
    /// otherwise nil (the delta is buffered for a later flush).
    mutating func accept(_ text: String, now: UInt64) -> String? {
        pending += text
        guard !pending.isEmpty else { return nil }
        let due: Bool
        if let last = lastFlushNanos {
            due = pending.count >= maxChars || now &- last >= minIntervalNanos
        } else {
            due = true   // first chunk always flushes
        }
        return due ? take(now: now) : nil
    }

    /// Flush any remaining buffered text (call at stream end / cancel). Returns nil
    /// when nothing is buffered.
    mutating func drain() -> String? {
        guard !pending.isEmpty else { return nil }
        return take(now: lastFlushNanos ?? 0)
    }

    private mutating func take(now: UInt64) -> String {
        let out = pending
        pending = ""
        lastFlushNanos = now
        return out
    }
}
