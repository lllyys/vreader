// Purpose: Private subview helpers for `StatsCustomRangePicker` — kept
// here so the parent file stays under the ~300-line guideline (rule 50).
// All subviews are private to `StatsCustomRangePicker`'s extension and not
// reused elsewhere.
//
// @coordinates-with: StatsCustomRangePicker.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`

import SwiftUI

extension StatsCustomRangePicker {

    // MARK: - Date chip row

    @ViewBuilder
    var dateChipRow: some View {
        HStack(spacing: 8) {
            dateChip(label: "START", value: state.start,
                     active: state.phase == .empty || state.phase == .pickingEnd)
            Text("→")
                .foregroundStyle(Color(theme.subColor))
                .font(.system(size: 16))
            dateChip(label: "END", value: state.end,
                     active: state.phase == .pickingEnd && state.start != nil)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    func dateChip(label: String, value: Date?, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(active ? Color(theme.accentColor) : Color(theme.subColor))
            Text(value.map { formatChip($0) } ?? "Select")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(value == nil ? Color(theme.subColor) : Color(theme.inkColor))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(active ? Color(theme.accentColor) : Color(theme.ruleColor),
                        lineWidth: active ? 1.5 : 0.5)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(Color(theme.subColor).opacity(0.04)))
        )
    }

    // MARK: - Preset rail

    @ViewBuilder
    var presetRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(StatsCustomRangePreset.allCases, id: \.self) { preset in
                    Button(action: { applyPreset(preset) }) {
                        Text(preset.label)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color(theme.inkColor))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color(theme.subColor).opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statsCustomRangePreset-\(preset.rawValue)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Month header + grid

    @ViewBuilder
    var monthHeader: some View {
        HStack {
            Button(action: { stepMonth(-1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(theme.subColor).opacity(0.05)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("statsCustomRangePickerPrevMonth")
            Spacer()
            Text(monthHeaderTitle)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Color(theme.inkColor))
            Spacer()
            Button(action: { stepMonth(1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(theme.subColor).opacity(0.05)))
            }
            .buttonStyle(.plain)
            .disabled(!canStepForward)
            .accessibilityIdentifier("statsCustomRangePickerNextMonth")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    @ViewBuilder
    var monthGrid: some View {
        let cells = StatsCustomRangeMonthGrid.cells(
            forYear: viewYear, month: viewMonth, calendar: calendar
        )
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { c in
                    Text(c)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color(theme.subColor))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(cells.indices, id: \.self) { idx in
                    if let day = cells[idx] {
                        dayCell(day: day)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    @ViewBuilder
    func dayCell(day: Int) -> some View {
        let date = dateFor(day: day)
        let inRange = dateIsInRange(date)
        let isStart = state.start.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isEnd = state.end.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isToday = calendar.isDate(today, inSameDayAs: date)
        let isFuture = date > calendar.startOfDay(for: today)
        Button(action: { tapDay(day: day) }) {
            ZStack {
                if isStart || isEnd {
                    Circle().fill(Color(theme.accentColor))
                        .padding(2)
                } else if inRange {
                    Rectangle().fill(Color(theme.accentColor).opacity(0.18))
                }
                Text("\(day)")
                    .font(.system(size: 13.5, weight: isStart || isEnd ? .semibold : .medium).monospacedDigit())
                    .foregroundStyle(dayColor(isStart: isStart, isEnd: isEnd, isToday: isToday))
            }
            .frame(height: 36)
            .opacity(isFuture ? 0.32 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityIdentifier("statsCustomRangePickerDay-\(viewYear)-\(viewMonth)-\(day)")
    }

    // MARK: - Summary footer

    @ViewBuilder
    var summaryBar: some View {
        let summary: String = {
            switch state.phase {
            case .empty:      return "Pick a start date to begin."
            case .pickingEnd: return "Pick an end date."
            case .ready:
                guard let range = state.applyRange() else { return "" }
                let dc = range.dayCount(calendar: calendar)
                return "\(dc) day\(dc == 1 ? "" : "s")"
            case .allTime:    return "All time selected — applying enum window."
            }
        }()
        HStack {
            Text(summary)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(theme.subColor))
                .accessibilityIdentifier("statsCustomRangePickerSummary")
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .overlay(Rectangle()
            .fill(Color(theme.ruleColor))
            .frame(height: 0.5), alignment: .top)
    }
}
