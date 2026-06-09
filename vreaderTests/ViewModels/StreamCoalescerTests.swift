// Purpose: Tests for StreamCoalescer (Bug #323) — the per-token re-render-churn
// fix. The coalescer batches streamed deltas so the @Observable transcript is
// re-published at a capped rate instead of on every token (which saturated the
// main thread → whole-app freeze on long replies / 2nd+ message).

import Testing
@testable import vreader

@Suite("StreamCoalescer")
struct StreamCoalescerTests {

    // The first chunk always flushes promptly so the first token shows without
    // waiting for the batch threshold — UX parity with un-batched streaming.
    @Test func firstChunkFlushesImmediately() {
        var c = StreamCoalescer(maxChars: 64, minIntervalNanos: 33_000_000)
        #expect(c.accept("Hello", now: 0) == "Hello")
    }

    // Rapidly delivered tiny chunks (now barely advances) batch by char count:
    // a flush happens only when pending crosses maxChars, NOT per chunk.
    @Test func rapidTinyChunksBatchByCharCount() {
        var c = StreamCoalescer(maxChars: 10, minIntervalNanos: 1_000_000_000)
        var flushes: [String] = []
        // First chunk flushes (1 char shown promptly).
        if let f = c.accept("a", now: 0) { flushes.append(f) }
        // Next 25 single-char chunks at the same instant → batched in 10-char groups.
        for _ in 0..<25 { if let f = c.accept("x", now: 0) { flushes.append(f) } }
        if let f = c.drain() { flushes.append(f) }
        // 26 chars total ("a" + 25 "x"). Far fewer than 26 flushes.
        #expect(flushes.count < 26)
        #expect(flushes.joined() == "a" + String(repeating: "x", count: 25))
    }

    // No text is ever lost across coalescing — concatenated flushes equal input.
    @Test func losslessAcrossFlushesAndDrain() {
        var c = StreamCoalescer(maxChars: 8, minIntervalNanos: 33_000_000)
        let chunks = ["The ", "quick ", "brown ", "fox ", "jumps."]
        var out = ""
        for (i, ch) in chunks.enumerated() {
            if let f = c.accept(ch, now: UInt64(i)) { out += f }
        }
        if let f = c.drain() { out += f }
        #expect(out == chunks.joined())
    }

    // A time gap >= the interval forces a flush even below the char threshold,
    // so a slow trickle still updates the UI without waiting to fill a batch.
    @Test func timeIntervalForcesFlushBelowCharThreshold() {
        var c = StreamCoalescer(maxChars: 1000, minIntervalNanos: 33_000_000)
        _ = c.accept("first", now: 0)               // first chunk flushes, lastFlush=0
        #expect(c.accept("x", now: 10_000_000) == nil)   // +10ms < 33ms → buffered
        #expect(c.accept("y", now: 40_000_000) == "xy")  // +40ms >= 33ms → flush "xy"
    }

    // drain() on an empty buffer returns nil (nothing to flush).
    @Test func drainEmptyReturnsNil() {
        var c = StreamCoalescer(maxChars: 64, minIntervalNanos: 33_000_000)
        _ = c.accept("done", now: 0)
        #expect(c.drain() == nil)
    }
}
