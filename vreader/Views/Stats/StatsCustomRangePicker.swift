// Purpose: Feature #58 WI-6b — SwiftUI realization of the design's
// `CustomRangePickerSheet` (`stats-followups-artboards.jsx`). Pinned to:
//   - title bar (Cancel / "Custom range" / Apply)
//   - Start/End date chips
//   - Quick-preset rail (Last 7 / 14 / This month / Last month / This year /
//     All time)
//   - Month grid with chevron month-navigation
//   - Summary footer (empty / picking-end / ready / no-results-in-range)
//
// Pure state lives in StatsCustomRangePickerState (separate file) so the
// transitions are unit-testable without driving the SwiftUI view tree.
// Subview helpers (chips / grid / preset rail / summary) live in the
// `+Subviews.swift` companion file so this parent stays under the
// ~300-line guideline.
//
// @coordinates-with: StatsCustomRangePickerState.swift,
//   StatsCustomRangePicker+Subviews.swift, ReadingStatsCustomRange.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`

import SwiftUI

/// The design's `CustomRangePickerSheet`. Presented as a SwiftUI `.sheet`
/// over the stats dashboard.
struct StatsCustomRangePicker: View {

    // Internal to the +Subviews extension; nothing outside the type reads
    // these directly.
    let theme: ReaderThemeV2
    let today: Date
    let calendar: Calendar
    let onApply: (ReadingStatsCustomRange) -> Void
    let onAllTimeSelected: () -> Void
    let onCancel: () -> Void

    @State var state: StatsCustomRangePickerState
    @State var viewMonth: Int
    @State var viewYear: Int

    init(
        theme: ReaderThemeV2,
        existingRange: ReadingStatsCustomRange?,
        today: Date = Date(),
        calendar: Calendar = StatsCustomRangePicker.defaultCalendar(),
        onApply: @escaping (ReadingStatsCustomRange) -> Void,
        onAllTimeSelected: @escaping () -> Void = {},
        onCancel: @escaping () -> Void
    ) {
        self.theme = theme
        self.today = today
        self.calendar = calendar
        self.onApply = onApply
        self.onAllTimeSelected = onAllTimeSelected
        self.onCancel = onCancel

        let initial = StatsCustomRangePickerState(
            today: today, calendar: calendar, existingRange: existingRange
        )
        _state = State(initialValue: initial)

        // Anchor the month view on the existing range's start day (if any) or
        // today. Re-materialize through the calendar so a saved range from
        // another timezone still anchors on the SAME calendar day.
        let anchorDay = existingRange?.startDate(calendar: calendar) ?? today
        let comps = calendar.dateComponents([.year, .month], from: anchorDay)
        _viewMonth = State(initialValue: comps.month ?? 1)
        _viewYear = State(initialValue: comps.year ?? 2026)
    }

    /// Monday-first calendar per the design — kept here so the View's default
    /// initializer matches what the picker state expects.
    static func defaultCalendar() -> Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    // MARK: - Testing seam

    var pickerStateForTesting: StatsCustomRangePickerState { state }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            dateChipRow
            presetRail
            monthHeader
            monthGrid
            Spacer(minLength: 0)
            summaryBar
        }
        .background(Color(theme.paperColor))
        .accessibilityIdentifier("statsCustomRangePicker")
    }

    // MARK: - Title bar

    @ViewBuilder
    var titleBar: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(theme.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("statsCustomRangePickerCancel")

            Spacer()
            Text("Custom range")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(Color(theme.inkColor))
            Spacer()

            Button(action: applyTapped) {
                Text("Apply")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(state.canApply
                        ? Color(theme.accentColor)
                        : Color(theme.subColor))
            }
            .buttonStyle(.plain)
            .disabled(!state.canApply)
            .accessibilityIdentifier("statsCustomRangePickerApply")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(Rectangle()
            .fill(Color(theme.ruleColor))
            .frame(height: 0.5), alignment: .bottom)
    }

    // MARK: - Actions

    func tapDay(day: Int) {
        state.pickDate(dateFor(day: day))
    }

    func applyTapped() {
        guard let range = state.applyRange() else { return }
        onApply(range)
    }

    func applyPreset(_ preset: StatsCustomRangePreset) {
        state.selectPreset(preset)
        switch state.phase {
        case .ready:
            if let start = state.start {
                let comps = calendar.dateComponents([.year, .month], from: start)
                viewYear = comps.year ?? viewYear
                viewMonth = comps.month ?? viewMonth
            }
        case .allTime:
            onAllTimeSelected()
        default:
            break
        }
    }

    func stepMonth(_ delta: Int) {
        var newMonth = viewMonth + delta
        var newYear = viewYear
        while newMonth > 12 { newMonth -= 12; newYear += 1 }
        while newMonth < 1  { newMonth += 12; newYear -= 1 }
        viewYear = newYear; viewMonth = newMonth
    }

    var canStepForward: Bool {
        let todayComps = calendar.dateComponents([.year, .month], from: today)
        guard let ty = todayComps.year, let tm = todayComps.month else { return true }
        if viewYear < ty { return true }
        if viewYear == ty && viewMonth < tm { return true }
        return false
    }

    // MARK: - Helpers

    var monthHeaderTitle: String {
        let names = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December",
        ]
        let safeIndex = max(1, min(12, viewMonth)) - 1
        return "\(names[safeIndex]) \(viewYear)"
    }

    func dateFor(day: Int) -> Date {
        var comps = DateComponents()
        comps.year = viewYear; comps.month = viewMonth; comps.day = day
        return calendar.date(from: comps) ?? today
    }

    func dateIsInRange(_ date: Date) -> Bool {
        guard let s = state.start, let e = state.end else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: s) && day <= calendar.startOfDay(for: e)
    }

    func dayColor(isStart: Bool, isEnd: Bool, isToday: Bool) -> Color {
        if isStart || isEnd { return Color(theme.paperColor) }
        if isToday { return Color(theme.accentColor) }
        return Color(theme.inkColor)
    }

    func formatChip(_ date: Date) -> String {
        let comps = calendar.dateComponents([.month, .day, .year], from: date)
        let names = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        let monthIdx = max(1, min(12, comps.month ?? 1)) - 1
        return "\(names[monthIdx]) \(comps.day ?? 1), \(comps.year ?? 0)"
    }
}
