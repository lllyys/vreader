// Purpose: Helper for respecting the Reduce Motion accessibility setting.
// Returns nil animation when the user prefers reduced motion.
//
// Key decisions:
// - View modifier approach for easy adoption in SwiftUI views.
// - Reads @Environment(\.accessibilityReduceMotion) in the modifier.
// - Pure utility — no state, no side effects.

import SwiftUI

/// View modifier that conditionally applies animation based on Reduce Motion setting.
struct ReduceMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                } else if let animation {
                    transaction.animation = animation
                }
            }
    }
}

extension View {
    /// Applies the given animation only when Reduce Motion is off.
    /// When Reduce Motion is on, all animations on this view are suppressed.
    func motionSafeAnimation(_ animation: Animation? = .default) -> some View {
        modifier(ReduceMotionModifier(animation: animation))
    }
}
