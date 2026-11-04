import SwiftUI

/// Your time over any stretch of days — one day, a month, an interval or all of it —
/// picked on a calendar. Read-only: logging stays on the week.
struct StatsView: View {
    @Environment(Store.self) private var store
    @Binding var selection: StatsSelection

    @State private var hoveredID: UUID?
    /// The average last picked. It comes back whenever the selection is long enough for it.
    @State private var average: StatsSelection.Average = .total
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let byActivity = store.minutesByActivity(from: selection.start, to: selection.endExclusive)
        let counted = selection.countedDays(logged: store.loggedSpan)
        let averages = StatsSelection.averages(counted: counted)
        let shownAverage = averages.contains(average) ? average : .total
        // Every activity, with or without time here, so moving the selection only
        // resizes slices and the chart can animate it.
        let slices = store.orderedActivities.map {
            Slice(id: $0.id, name: $0.name,
                  minutes: StatsSelection.averaged(max(0, byActivity[$0.id] ?? 0),
                                                   over: counted, as: shownAverage),
                  colorSlot: $0.colorSlot)
        }
        let total = slices.reduce(0) { $0 + $1.minutes }

        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Picker("Show", selection: Binding(
                    get: { selection.mode },
                    set: { mode in change { selection.pick(mode, logged: store.loggedSpan) } }
                )) {
                    ForEach(StatsSelection.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                StatsCalendar(selection: $selection, onClick: { day in change { selection.click(day) } })
            }

            VStack(spacing: 8) {
                DonutChart(slices: slices, hoveredID: hoveredID, onHover: { hoveredID = $0 })
                    .frame(height: 220)
                if total > 0, counted > 1 {
                    Text(shownAverage == .total
                         ? "\(counted) days · \(Duration.format(minutes: total / counted)) a day"
                         : "Averaged over \(counted) days")
                        .font(.callout)
                        .foregroundStyle(Ink.muted)
                        .monospacedDigit()
                }
            }

            VStack(spacing: 10) {
                if averages.count > 1 {
                    Picker("Average", selection: Binding(
                        get: { shownAverage },
                        set: { picked in change { average = picked } }
                    )) {
                        ForEach(averages) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .help("Show the whole stretch, or a typical day, week or month of it")
                }

                breakdown(slices.filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }, total: total)
            }
        }
    }

    private func change(_ update: () -> Void) {
        withAnimation(reduceMotion ? Motion.reduced : Motion.snappy, update)
    }

    // MARK: - Breakdown

    /// What the chart is made of, biggest first.
    @ViewBuilder
    private func breakdown(_ shown: [Slice], total: Int) -> some View {
        VStack(spacing: RowMetrics.spacing) {
            if shown.isEmpty {
                Text(selection.mode == .allTime ? "Nothing logged yet" : "Nothing logged")
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            ForEach(shown) { slice in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Palette.color(slot: slice.colorSlot))
                        .frame(width: 10, height: 10)
                    Text(slice.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text("\(Int((Double(slice.minutes) / Double(max(total, 1)) * 100).rounded()))%")
                        .foregroundStyle(Ink.muted)
                    Text(Duration.format(minutes: slice.minutes))
                        .frame(minWidth: 64, alignment: .trailing)
                }
                .monospacedDigit()
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hoveredID == slice.id ? Color.primary.opacity(0.06) : .clear)
                )
                .contentShape(Rectangle())
                .onHover { hoveredID = $0 ? slice.id : (hoveredID == slice.id ? nil : hoveredID) }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quinary))
    }
}

/// A month at a time, Monday first. The selected days are joined by one band, and a
/// dot marks each day with time logged on it.
private struct StatsCalendar: View {
    @Environment(Store.self) private var store
    @Binding var selection: StatsSelection
    let onClick: (Date) -> Void

    @State private var hoveredDay: Date?

    private let cellHeight: CGFloat = 32

    /// Six full weeks, so the grid keeps its height from month to month.
    private var days: [Date] {
        let first = WeekMath.weekStart(for: selection.shownMonth)
        return (0..<42).map { WeekMath.addDays($0, to: first) }
    }

    var body: some View {
        let days = days
        let logged = store.minutesByDay(from: days[0], to: WeekMath.addDays(1, to: days[41]))

        VStack(spacing: 6) {
            header

            HStack(spacing: 0) {
                ForEach(days.prefix(7), id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                            cell(day, column: WeekMath.days(from: days[week * 7], to: day),
                                 logged: (logged[day] ?? 0) > 0)
                        }
                    }
                }
            }

            Text(selection.hint ?? " ")
                .font(.caption)
                .foregroundStyle(Ink.muted)
                .opacity(selection.hint == nil ? 0 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quinary))
    }

    private var header: some View {
        HStack {
            Text(selection.shownMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button("Today") {
                selection.shownMonth = WeekMath.monthStart(for: Date())
            }
            .buttonStyle(.borderless)
            .disabled(selection.shownMonth == WeekMath.monthStart(for: Date()))
            HStack(spacing: 2) {
                monthButton(-1, systemImage: "chevron.left", help: "Previous month")
                monthButton(1, systemImage: "chevron.right", help: "Next month")
            }
        }
        .padding(.leading, 4)
    }

    private func monthButton(_ n: Int, systemImage: String, help: String) -> some View {
        Button {
            selection.shownMonth = WeekMath.addMonths(n, to: selection.shownMonth)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func cell(_ day: Date, column: Int, logged: Bool) -> some View {
        let selected = selection.contains(day)
        let isEnd = day == selection.start || day == selection.end
        let inMonth = WeekMath.monthStart(for: day) == selection.shownMonth
        let isToday = day == WeekMath.startOfDay(Date())

        return Button { onClick(day) } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: isToday || isEnd ? .semibold : .regular))
                    .foregroundStyle(
                        isEnd ? AnyShapeStyle(.white)
                        : isToday ? AnyShapeStyle(.tint)
                        : inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
                    )
                Circle()
                    .fill(isEnd ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(Ink.muted))
                    .frame(width: 4, height: 4)
                    .opacity(logged ? 1 : 0)
            }
            .frame(width: cellHeight, height: cellHeight)
            .background {
                if isEnd {
                    Circle().fill(.tint)
                } else if hoveredDay == day {
                    Circle().fill(Color.primary.opacity(0.07))
                }
            }
            .frame(maxWidth: .infinity)
            .background { band(day, column: column, selected: selected) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredDay = $0 ? day : (hoveredDay == day ? nil : hoveredDay) }
        .help(day.formatted(date: .complete, time: .omitted))
    }

    /// The tinted strip joining the selected days. It runs from the first day's circle
    /// to the last day's, and is rounded off where a week wraps onto the next row.
    @ViewBuilder
    private func band(_ day: Date, column: Int, selected: Bool) -> some View {
        if selected, selection.start != selection.end {
            let tint = Color.accentColor.opacity(0.18)
            let radius = cellHeight / 2
            HStack(spacing: 0) {
                Rectangle().fill(day == selection.start ? .clear : tint)
                Rectangle().fill(day == selection.end ? .clear : tint)
            }
            .frame(height: cellHeight)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: column == 0 ? radius : 0,
                bottomLeadingRadius: column == 0 ? radius : 0,
                bottomTrailingRadius: column == 6 ? radius : 0,
                topTrailingRadius: column == 6 ? radius : 0,
                style: .continuous
            ))
        }
    }
}
