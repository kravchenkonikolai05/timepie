import Foundation

/// The stretch of days the stats page shows, and how clicks on its calendar move it.
///
/// A click shows that day. In Interval, clicks come in pairs instead: the first day,
/// then the last, and the click after that starts the next interval.
struct StatsSelection: Equatable {
    enum Mode: String, CaseIterable, Identifiable {
        case day = "Day"
        case month = "Month"
        case interval = "Interval"
        case allTime = "All Time"

        var id: Self { self }
    }

    private(set) var mode: Mode = .day
    /// The first and last day shown, both included.
    private(set) var start: Date
    private(set) var end: Date
    /// The month on the calendar, which needn't be the one selected.
    var shownMonth: Date
    /// The day last clicked: where Day and Interval begin when picked.
    private var focus: Date
    /// An interval's first day was just clicked, so the next click ends it.
    private var anchored = false

    init(today: Date = Date()) {
        let day = WeekMath.startOfDay(today)
        start = day
        end = day
        focus = day
        shownMonth = WeekMath.monthStart(for: day)
    }

    /// The day after `end`, for queries that take a half-open range.
    var endExclusive: Date { WeekMath.addDays(1, to: end) }

    var dayCount: Int { WeekMath.days(from: start, to: end) + 1 }

    func contains(_ day: Date) -> Bool { day >= start && day <= end }

    /// What the next click does, while that isn't obvious.
    var hint: String? {
        switch (mode, anchored) {
        case (.interval, false) where start == end: "Click the first day"
        case (.interval, true): "Click the last day"
        default: nil
        }
    }

    mutating func click(_ date: Date) {
        let day = WeekMath.startOfDay(date)
        focus = day
        if mode == .interval && anchored {
            guard day != start else { return }
            let first = start
            start = min(first, day)
            end = max(first, day)
            anchored = false
        } else {
            // Outside Interval a click is just that day, even from Month or All Time.
            if mode != .interval { mode = .day }
            start = day
            end = day
            anchored = mode == .interval
        }
    }

    /// `logged` is the first and last day with time on it, for All Time.
    mutating func pick(_ mode: Mode, logged: ClosedRange<Date>?, today: Date = Date()) {
        self.mode = mode
        anchored = false
        switch mode {
        case .day, .interval:
            start = focus
            end = focus
        case .month:
            start = shownMonth
            end = WeekMath.addDays(-1, to: WeekMath.monthEnd(for: shownMonth))
        case .allTime:
            let today = WeekMath.startOfDay(today)
            start = min(logged?.lowerBound ?? today, today)
            end = max(logged?.upperBound ?? today, today)
            return
        }
        shownMonth = WeekMath.monthStart(for: start)
    }

    /// The previous or next day, month or interval of the same length.
    mutating func step(_ n: Int) {
        anchored = false
        switch mode {
        case .day:
            start = WeekMath.addDays(n, to: start)
            end = start
        case .month:
            start = WeekMath.addMonths(n, to: start)
            end = WeekMath.addDays(-1, to: WeekMath.monthEnd(for: start))
        case .interval:
            let length = dayCount
            start = WeekMath.addDays(n * length, to: start)
            end = WeekMath.addDays(n * length, to: end)
        case .allTime:
            return
        }
        focus = start
        shownMonth = WeekMath.monthStart(for: start)
    }

    // MARK: - Averages

    /// How the breakdown reads: the whole stretch, or a typical day, week or month of it.
    enum Average: String, CaseIterable, Identifiable {
        case total = "Total"
        case day = "Per Day"
        case week = "Per Week"
        case month = "Per Month"

        var id: Self { self }

        /// How many days one of it is. A month is an average one.
        var days: Double {
            switch self {
            case .total: 0
            case .day: 1
            case .week: 7
            case .month: 365.2425 / 12
            }
        }
    }

    /// The days an average is taken over: the selected ones you could have logged,
    /// so neither days still to come nor days from before you started count as zero.
    func countedDays(logged: ClosedRange<Date>?, today: Date = Date()) -> Int {
        guard let logged else { return 0 }
        let first = max(start, logged.lowerBound)
        let last = min(end, max(WeekMath.startOfDay(today), logged.upperBound))
        return max(0, WeekMath.days(from: first, to: last) + 1)
    }

    /// The averages worth offering over `counted` days: each needs at least two of
    /// its unit, or it would just be the total again.
    static func averages(counted: Int) -> [Average] {
        Average.allCases.filter { $0 == .total || Double(counted) >= 2 * $0.days }
    }

    /// `minutes` over `counted` days, as a typical `average`.
    static func averaged(_ minutes: Int, over counted: Int, as average: Average) -> Int {
        guard average != .total, counted > 0 else { return minutes }
        return Int((Double(minutes) * average.days / Double(counted)).rounded())
    }

    // MARK: - Labels

    /// "Today", "Mon, Oct 26", "October 2026", "Oct 3 – 17", "All Time".
    var title: String {
        switch mode {
        case .allTime:
            return "All Time"
        case .month:
            return start.formatted(.dateTime.month(.wide).year())
        case .day, .interval:
            if start == end { return Self.dayTitle(start) }
            return Self.rangeTitle(start, end)
        }
    }

    /// The step the toolbar arrows take, for their labels.
    var unitName: String {
        switch mode {
        case .day: "Day"
        case .month: "Month"
        case .interval, .allTime: "Interval"
        }
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return isThisYear(day)
            ? day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : day.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Left to the system, which knows how a range of dates reads in your language.
    private static func rangeTitle(_ start: Date, _ end: Date) -> String {
        let style = Date.IntervalFormatStyle().month(.abbreviated).day()
        return (start..<end).formatted(isThisYear(start) && isThisYear(end) ? style : style.year())
    }

    private static func isThisYear(_ day: Date) -> Bool {
        let calendar = WeekMath.calendar
        return calendar.component(.year, from: day) == calendar.component(.year, from: Date())
    }
}
