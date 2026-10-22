import SwiftUI

/// Draws the selected template's content. Sizes are in canvas points (the phone screen, ~400 wide).
struct WallpaperLayoutView: View {
    let config: WallpaperConfig
    let content: WallpaperContent
    let size: CGSize

    var body: some View {
        Group {
            switch config.layout {
            case .classic: panel { ClassicLayout(config: config, content: content) }
            case .monthEvents: panel { MonthEventsLayout(config: config, content: content) }
            case .week: WeekLayout(config: config, content: content)
            case .timeline: panel { TimelineLayout(config: config, content: content) }
            case .today: TodayLayout(config: config, content: content)
            case .matrix: MatrixLayout(config: config, content: content)
            case .yearProgress: YearProgressLayout(config: config)
            case .sticky: StickyNoteLayout(config: config, content: content)
            }
        }
        .foregroundStyle(config.foreground)
    }

    private func panel(@ViewBuilder _ inner: () -> some View) -> some View {
        inner()
            .padding(config.panel == .clear ? 4 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wallpaperCard(config)
    }
}

extension View {
    /// Background card in the configured panel style.
    func wallpaperCard(_ config: WallpaperConfig, radius: CGFloat = 26) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            switch config.panel {
            case .glass:
                shape.fill((config.lightText ? Color.black : Color.white).opacity(0.28))
                    .overlay(shape.stroke(config.foreground.opacity(0.18), lineWidth: 0.8))
            case .solid:
                shape.fill((config.lightText ? Color.black : Color.white).opacity(0.72))
            case .clear:
                EmptyView()
            }
        }
    }
}

private func rounded(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

private func timeRange(_ event: AgendaEvent) -> String {
    if event.isAllDay { return String(localized: "Cả ngày") }
    return "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
}

// MARK: - Classic (month + agenda + tasks + note)

private struct ClassicLayout: View {
    let config: WallpaperConfig
    let content: WallpaperContent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if config.showCalendar {
                MiniMonthView(
                    month: content.date, busyDays: content.busyDays, marker: CalendarPrefs.todayMarker,
                    accent: config.accent, foreground: config.foreground, fontSize: 13
                )
            }
            if config.showAgenda && !content.events.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(content.events.prefix(3)) { event in
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title).font(rounded(14, .semibold)).lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(Calendar.current.isDateInToday(event.start) ? event.timeText
                                         : event.start.formatted(.dateTime.weekday().hour().minute()))
                                    if let loc = event.location, !loc.isEmpty { Text("· \(loc)").lineLimit(1) }
                                }
                                .font(rounded(11))
                                .opacity(0.75)
                            }
                        }
                    }
                }
            }
            if config.showTasks && !content.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(content.tasks.prefix(4)) { task in
                        HStack(spacing: 7) {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(config.accent)
                            Text(task.text).font(rounded(13)).lineLimit(1)
                        }
                    }
                }
            }
            if config.showNote, let body = content.noteBody, let title = content.noteTitle {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(rounded(14, .bold)).foregroundStyle(config.accent)
                    if !body.isEmpty && body != title {
                        Text(body).font(rounded(13, .regular)).lineLimit(5)
                    }
                }
            }
        }
    }
}

// MARK: - Month with event bars

private struct MonthEventsLayout: View {
    let config: WallpaperConfig
    let content: WallpaperContent

    var body: some View {
        let cal = CalendarPrefs.calendar
        let grid = MonthGrid(month: content.date, calendar: cal)
        VStack(alignment: .leading, spacing: 8) {
            Text(grid.title.capitalized).font(rounded(16, .bold)).foregroundStyle(config.accent)
            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(grid.weekdaySymbols.enumerated()), id: \.offset) { _, s in
                        Text(s).font(rounded(10, .semibold)).opacity(0.55).frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            cell(day, cal: cal)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: Date?, cal: Calendar) -> some View {
        if let day {
            let isToday = cal.isDateInToday(day)
            let events = content.events(on: day, calendar: cal)
            VStack(spacing: 2) {
                ZStack {
                    if isToday {
                        switch CalendarPrefs.todayMarker {
                        case .ring: Circle().stroke(config.accent, lineWidth: 1.6)
                        case .square: RoundedRectangle(cornerRadius: 5).fill(config.accent)
                        case .dot: Circle().fill(config.accent).frame(width: 4, height: 4).offset(y: 10)
                        }
                    }
                    Text("\(cal.component(.day, from: day))")
                        .font(rounded(12, isToday ? .heavy : .medium))
                        .monospacedDigit()
                        .foregroundStyle(isToday && CalendarPrefs.todayMarker == .square ? Color.white : config.foreground)
                }
                .frame(width: 22, height: 22)
                ForEach(events.prefix(2)) { event in
                    Capsule().fill(event.color).frame(height: 4)
                }
                if events.count < 2 { Color.clear.frame(height: CGFloat(2 - events.count) * 6) }
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(height: 34).frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Week columns (Ink "Timetable")

private struct WeekLayout: View {
    let config: WallpaperConfig
    let content: WallpaperContent

    var body: some View {
        let cal = CalendarPrefs.calendar
        let start = cal.dateInterval(of: .weekOfYear, for: content.date)?.start ?? cal.startOfDay(for: content.date)
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
        HStack(alignment: .top, spacing: 3) {
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                VStack(spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated))).font(rounded(10, .semibold)).opacity(0.75)
                    Text("\(cal.component(.day, from: day))").font(rounded(15, .bold))
                    ForEach(content.events(on: day, calendar: cal).prefix(4)) { event in
                        VStack(alignment: .leading, spacing: 1) {
                            if !event.isAllDay {
                                Text(event.start.formatted(date: .omitted, time: .shortened))
                                    .font(rounded(7, .semibold)).opacity(0.7)
                            }
                            Text(event.title).font(rounded(8, .semibold)).lineLimit(2)
                        }
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(event.color.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
                .background(isToday ? config.accent.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(8)
        .wallpaperCard(config, radius: 18)
    }
}

// MARK: - Multi-day timeline

private struct TimelineLayout: View {
    let config: WallpaperConfig
    let content: WallpaperContent

    var body: some View {
        let cal = CalendarPrefs.calendar
        let today = cal.startOfDay(for: content.date)
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: today)! }
            .filter { !content.events(on: $0, calendar: cal).isEmpty }
            .prefix(4)
        VStack(alignment: .leading, spacing: 10) {
            Text("Lịch trình").font(.system(size: 18, weight: .semibold, design: .serif))
            if days.isEmpty {
                Text("Không có sự kiện trong 7 ngày tới").font(rounded(13)).opacity(0.7)
            }
            ForEach(Array(days), id: \.self) { day in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(rounded(10, .semibold)).opacity(0.7)
                        Text("\(cal.component(.day, from: day))").font(rounded(16, .bold))
                            .foregroundStyle(cal.isDateInToday(day) ? config.accent : config.foreground)
                    }
                    .frame(width: 34)
                    Rectangle().fill(config.foreground.opacity(0.3)).frame(width: 1)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(content.events(on: day, calendar: cal).prefix(3)) { event in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title).font(rounded(12, .semibold)).lineLimit(1)
                                Label(timeRange(event), systemImage: "clock").font(rounded(9)).opacity(0.75)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(event.color.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Today's events

private struct TodayLayout: View {
    let config: WallpaperConfig
    let content: WallpaperContent

    var body: some View {
        let cal = CalendarPrefs.calendar
        let remaining = content.events(on: content.date, calendar: cal).filter { $0.end > Date() || $0.isAllDay }
        // Late in the day, show tomorrow instead of an empty list.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: content.date)!
        let showsTomorrow = remaining.isEmpty && !content.events(on: tomorrow, calendar: cal).isEmpty
        let events = showsTomorrow ? content.events(on: tomorrow, calendar: cal) : remaining
        let dueToday = content.tasks.filter { $0.due.map { cal.isDateInToday($0) || $0 < Date() } ?? false }
        VStack(alignment: .leading, spacing: 14) {
            Text(showsTomorrow ? "Ngày mai" : "Hôm nay")
                .font(rounded(13, .bold))
                .textCase(.uppercase)
                .foregroundStyle(config.accent)
            if events.isEmpty && dueToday.isEmpty {
                Text("Hôm nay thật nhẹ nhàng ✨").font(rounded(16, .semibold))
            }
            ForEach(events.prefix(4)) { event in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(rounded(17, .semibold)).lineLimit(1)
                        if let notes = event.notes, !notes.isEmpty {
                            Text(notes).font(rounded(12)).lineLimit(1).opacity(0.8)
                        }
                        Label(timeRange(event), systemImage: "clock").font(rounded(12)).opacity(0.8)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(dueToday.prefix(3)) { task in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(config.accent).frame(width: 4, height: 22)
                    Image(systemName: "circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(config.accent)
                    Text(task.text).font(rounded(15, .medium)).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(config.lightText ? 0.35 : 0), radius: 4)
    }
}

// MARK: - Task board (Do / Plan / No date / Done)

private struct MatrixLayout: View {
    let config: WallpaperConfig
    let content: WallpaperContent

    var body: some View {
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let now = content.tasks.filter { ($0.due ?? .distantFuture) < endOfToday }
        let later = content.tasks.filter { ($0.due ?? .distantPast) >= endOfToday }
        let someday = content.tasks.filter { $0.due == nil }
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                quadrant("Hôm nay", "flame", now)
                quadrant("Sắp tới", "calendar", later)
            }
            GridRow {
                quadrant("Chưa hạn", "tray", someday)
                quadrant("Đã xong", "checkmark.seal", content.doneTasks)
            }
        }
    }

    private func quadrant(_ title: LocalizedStringKey, _ symbol: String, _ tasks: [WallpaperContent.TaskLine]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(rounded(12, .bold)).foregroundStyle(config.accent)
            ForEach(tasks.prefix(4)) { task in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                        .font(.system(size: 9, weight: .semibold))
                    Text(task.text).font(rounded(10)).lineLimit(2)
                        .strikethrough(task.isDone)
                        .opacity(task.isDone ? 0.6 : 1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .wallpaperCard(config, radius: 14)
    }
}

// MARK: - Year progress + countdown

private struct YearProgressLayout: View {
    let config: WallpaperConfig

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let year = cal.dateInterval(of: .year, for: now)!
        let days = cal.range(of: .day, in: .year, for: now)?.count ?? 365
        let dayIndex = (cal.ordinality(of: .day, in: .year, for: now) ?? 1) - 1
        let progress = now.timeIntervalSince(year.start) / year.duration
        let remaining = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: config.countdownTarget)).day ?? 0
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                HStack {
                    Text(now.formatted(.dateTime.year())).font(rounded(12, .semibold))
                    Spacer()
                    Text(progress.formatted(.percent.precision(.fractionLength(0)))).font(rounded(12, .semibold))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(config.foreground.opacity(0.2))
                        Capsule().fill(config.accent).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 5)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(9), spacing: 6), count: 21), spacing: 6) {
                ForEach(0..<days, id: \.self) { i in
                    Circle()
                        .fill(i < dayIndex ? config.foreground.opacity(0.85) : i == dayIndex ? config.accent : config.foreground.opacity(0.22))
                        .frame(width: 9, height: 9)
                }
            }
            VStack(spacing: 0) {
                Text("\(remaining)").font(rounded(46, .bold)).monospacedDigit()
                Text(config.countdownLabel).font(rounded(13)).opacity(0.85)
            }
        }
        .padding(16)
        .wallpaperCard(config)
    }
}

// MARK: - Paper note with a binder clip

private struct StickyNoteLayout: View {
    let config: WallpaperConfig
    let content: WallpaperContent

    private var lines: [WallpaperContent.TaskLine] {
        if !content.noteItems.isEmpty { return content.noteItems }
        if let body = content.noteBody, !body.isEmpty {
            return body.split(separator: "\n").map { WallpaperContent.TaskLine(id: UUID(), text: String($0), isDone: false, due: nil) }
        }
        return content.tasks
    }

    var body: some View {
        let ink = Color(hex: "#2B2B2B")
        VStack(alignment: .leading, spacing: 9) {
            Text(content.noteTitle ?? String(localized: "Việc cần làm"))
                .font(.custom("Noteworthy-Bold", size: 22))
                .frame(maxWidth: .infinity)
                .padding(.top, 26)
            ForEach(lines.prefix(7)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: line.isDone ? "checkmark.circle" : "circle").font(.system(size: 11, weight: .semibold))
                    Text(line.text).font(.custom("Noteworthy-Light", size: 15)).lineLimit(1)
                        .strikethrough(line.isDone)
                }
                .opacity(line.isDone ? 0.55 : 1)
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 22).padding(.bottom, 22)
        .frame(maxWidth: 300, alignment: .leading)
        .background {
            // Ruled lines live in an overlay so they never make the paper taller than its text.
            Color(hex: "#FBF8EF")
                .overlay(alignment: .top) {
                    VStack(spacing: 23) {
                        ForEach(0..<14, id: \.self) { _ in Rectangle().fill(Color(hex: "#9DB7D9").opacity(0.45)).frame(height: 0.6) }
                    }
                    .padding(.top, 66)
                }
                .clipped()
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .overlay(alignment: .top) {
            // Binder clip straddling the top edge of the paper.
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "#3A3A3A"), lineWidth: 3)
                    .frame(width: 34, height: 16)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#2E2E2E"))
                    .frame(width: 60, height: 22)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .offset(y: -20)
        }
        .rotationEffect(.degrees(-2))
        .frame(maxWidth: .infinity)
    }
}
