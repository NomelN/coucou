import SwiftUI

/// Month grid of the Calendar card, like the menu bar calendar: today highlighted, up to three
/// dots (calendar colors) under the days that have events, past days dimmed. Rows shrink to fit
/// `height`, so a six-week month still fits the 98 pt overview card. A tap gives the day.
struct CalendarMonthGrid: View {
    /// Any date in the month shown.
    let month: Date
    /// Day of the month → colors of the calendars that have events that day (3 at most).
    let eventColors: [Int: [String]]
    var selectedDay: Int? = nil
    var accent: Color = Color(hex: "#FF7A45")
    /// Height for the weekday row and the weeks together.
    var height: CGFloat = 76
    var onTapDay: (Date) -> Void = { _ in }

    private var cal: Calendar { Calendar.current }

    private var monthStart: Date {
        cal.dateInterval(of: .month, for: month)?.start ?? month
    }

    /// The month's days by week, nil for the blanks before the 1st and after the last day.
    private var weeks: [[Int?]] {
        let days = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let lead = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead) + (1...days).map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Day of the month for today when it is in this month.
    private var today: Int? {
        let now = Date()
        guard cal.isDate(now, equalTo: monthStart, toGranularity: .month) else { return nil }
        return cal.component(.day, from: now)
    }

    private var isPastMonth: Bool { monthStart < (cal.dateInterval(of: .month, for: Date())?.start ?? Date()) }

    private static let weekdayRow: CGFloat = 9

    var body: some View {
        let rows = weeks
        let rowHeight = min(14, (height - Self.weekdayRow) / CGFloat(max(rows.count, 1)))
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundColor(Color(hex: "#5F646D"))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Self.weekdayRow)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cell(day, rowHeight: rowHeight)
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: Int?, rowHeight: CGFloat) -> some View {
        if let day {
            let isToday = day == today
            let isPast = isPastMonth || (today.map { day < $0 } ?? false)
            let colors = eventColors[day] ?? []
            Button {
                if let date = cal.date(byAdding: .day, value: day - 1, to: monthStart) { onTapDay(date) }
            } label: {
                ZStack {
                    if isToday {
                        Capsule().fill(accent).frame(width: 17, height: rowHeight - 1)
                    } else if day == selectedDay {
                        Capsule().stroke(accent.opacity(0.8), lineWidth: 1).frame(width: 17, height: rowHeight - 1)
                    }
                    Text("\(day)")
                        .font(.system(size: 8.5, weight: isToday || !colors.isEmpty ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundColor(isToday ? .white
                                         : isPast ? Color(hex: "#5F646D")
                                         : colors.isEmpty ? Color(hex: "#9398A1") : Color(hex: "#E6E8EC"))
                        .offset(y: colors.isEmpty ? 0 : -1.5)
                    if !colors.isEmpty {
                        HStack(spacing: 1.5) {
                            ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, hex in
                                Circle().fill(isToday ? Color.white : Color(hex: hex))
                                    .frame(width: 2.5, height: 2.5)
                            }
                        }
                        .opacity(isPast && !isToday ? 0.5 : 1)
                        .offset(y: rowHeight / 2 - 2.5)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
        }
    }
}
