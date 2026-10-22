import SwiftUI

/// Compact month calendar used in widgets, wallpapers and the app.
struct MiniMonthView: View {
    var month: Date = Date()
    var busyDays: Set<Date> = []
    var marker: TodayMarker = CalendarPrefs.todayMarker
    var accent: Color = .accentColor
    var foreground: Color = .primary
    var fontSize: CGFloat = 11
    var showTitle: Bool = true
    var calendar: Calendar = CalendarPrefs.calendar

    var body: some View {
        let grid = MonthGrid(month: month, calendar: calendar)
        VStack(alignment: .leading, spacing: fontSize * 0.45) {
            if showTitle {
                Text(grid.title.capitalized)
                    .font(.system(size: fontSize * 1.15, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }
            Grid(horizontalSpacing: 0, verticalSpacing: fontSize * 0.25) {
                GridRow {
                    ForEach(Array(grid.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: fontSize * 0.8, weight: .semibold, design: .rounded))
                            .foregroundStyle(foreground.opacity(0.55))
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            dayCell(day)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let isToday = calendar.isDateInToday(day)
            let busy = busyDays.contains(calendar.startOfDay(for: day))
            let size = fontSize * 1.75
            ZStack {
                if isToday {
                    switch marker {
                    case .ring:
                        Circle().stroke(accent, lineWidth: max(1, fontSize * 0.13))
                    case .square:
                        RoundedRectangle(cornerRadius: fontSize * 0.35).fill(accent)
                    case .dot:
                        EmptyView()
                    }
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: fontSize, weight: isToday ? .heavy : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isToday && marker == .square ? Color.white : (isToday ? accent : foreground))
                if busy || (isToday && marker == .dot) {
                    Circle()
                        .fill(isToday && marker == .dot ? accent : foreground.opacity(0.6))
                        .frame(width: fontSize * 0.28, height: fontSize * 0.28)
                        .offset(y: fontSize * 0.72)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(height: fontSize * 1.75).frame(maxWidth: .infinity)
        }
    }
}

/// Checkbox glyph shared by app and widgets.
struct CheckGlyph: View {
    var isDone: Bool
    var tint: Color = .accentColor
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(isDone ? tint : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
    }
}
