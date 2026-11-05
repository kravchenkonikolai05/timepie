import Foundation

/// Weeks start on Monday.
enum WeekMath {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func weekStart(for date: Date) -> Date {
        let cal = calendar
        guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else {
            return cal.startOfDay(for: date)
        }
        return cal.startOfDay(for: interval.start)
    }

    static func weekEnd(for date: Date) -> Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart(for: date)) ?? date
    }

    static func addWeeks(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .weekOfYear, value: n, to: date) ?? date
    }

    static func addDays(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: date) ?? date
    }

    static func monthStart(for date: Date) -> Date {
        let cal = calendar
        guard let interval = cal.dateInterval(of: .month, for: date) else {
            return cal.startOfDay(for: date)
        }
        return cal.startOfDay(for: interval.start)
    }

    /// The first day of the next month.
    static func monthEnd(for date: Date) -> Date {
        addMonths(1, to: monthStart(for: date))
    }

    static func addMonths(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: date) ?? date
    }

    /// Whole days from one start-of-day to another.
    static func days(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(start), to: startOfDay(end)).day ?? 0
    }

    static func isSameWeek(_ a: Date, _ b: Date) -> Bool {
        weekStart(for: a) == weekStart(for: b)
    }

    static func daysOfWeek(containing date: Date) -> [Date] {
        let start = weekStart(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// "Sep 15 – 21" / "Sep 29 – Oct 5"
    static func weekLabel(for date: Date) -> String {
        let start = weekStart(for: date)
        let end = addDays(6, to: start)
        let month = DateFormatter()
        month.dateFormat = "MMM d"
        let dayOnly = DateFormatter()
        dayOnly.dateFormat = "d"
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        return sameMonth
            ? "\(month.string(from: start)) – \(dayOnly.string(from: end))"
            : "\(month.string(from: start)) – \(month.string(from: end))"
    }

    /// Days of a week counted so far: up to and including today in this week, all
    /// seven in a past one, none in a week still to come.
    static func daysElapsed(inWeek week: Date, today: Date) -> Int {
        let start = weekStart(for: week)
        let n = days(from: start, to: today) + 1
        return min(7, max(0, n))
    }

    /// "Mon Sep 21"
    static func dayLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: date)
    }
}

/// Durations read as "8h 30m".
enum Duration {
    static func format(minutes: Int) -> String {
        let m = max(0, minutes)
        let h = m / 60
        let mins = m % 60
        if h == 0 { return "\(mins)m" }
        if mins == 0 { return "\(h)h" }
        return "\(h)h \(mins)m"
    }

    /// Hours to one decimal, roughly: "~3,5h", "~2h" — in the user's own number style.
    static func approxHours(minutes: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return "~\(f.string(from: NSNumber(value: max(0, minutes) / 60)) ?? "0")h"
    }

    /// A running stopwatch: "12:34", or "1:02:15" once it passes an hour.
    static func clock(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    /// Accepts "1h45", "1h 45m", "90", "90m", "1.5h", "2h".
    static func parse(_ raw: String) -> Int? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }

        if let hIndex = s.firstIndex(of: "h") {
            let hPart = String(s[s.startIndex..<hIndex]).trimmingCharacters(in: .whitespaces)
            let rest = String(s[s.index(after: hIndex)...])
                .replacingOccurrences(of: "m", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let hours = Double(hPart) else { return nil }
            let extra = rest.isEmpty ? 0 : (Int(rest) ?? 0)
            return Int((hours * 60).rounded()) + extra
        }

        let cleaned = s.replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces)
        if let mins = Int(cleaned) { return mins }
        if let dec = Double(cleaned) { return Int((dec * 60).rounded()) }
        return nil
    }
}
