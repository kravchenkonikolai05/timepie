import SwiftUI

/// Every amount logged into the viewed week, newest first, grouped by the day you
/// added it — so you can check whether you already logged something, and take back
/// what you logged twice. A deletion is one ⌘Z away, like any other edit.
struct LogView: View {
    @Environment(Store.self) private var store
    let weekStart: Date

    @State private var hoveredID: UUID?

    private struct Line: Identifiable {
        let entry: Entry
        let activity: Activity
        var id: UUID { entry.id }
    }

    /// Entries whose activity is gone count nowhere else, so they're left out here too.
    private var lines: [Line] {
        let byID = Dictionary(uniqueKeysWithValues: store.activities.map { ($0.id, $0) })
        return store.entries(from: weekStart, to: WeekMath.weekEnd(for: weekStart))
            .compactMap { entry in byID[entry.activityID].map { Line(entry: entry, activity: $0) } }
            .sorted { $0.entry.createdAt > $1.entry.createdAt }
    }

    /// Consecutive lines added on the same day, under that day.
    private var sections: [(day: Date, lines: [Line])] {
        var result: [(day: Date, lines: [Line])] = []
        for line in lines {
            let day = WeekMath.startOfDay(line.entry.createdAt)
            if result.last?.day == day {
                result[result.count - 1].lines.append(line)
            } else {
                result.append((day, [line]))
            }
        }
        return result
    }

    var body: some View {
        let sections = sections
        VStack(alignment: .leading, spacing: 0) {
            Text("Log")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            if sections.isEmpty {
                Text("Nothing logged this week")
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections, id: \.day) { section in
                            Section {
                                ForEach(section.lines) { row($0) }
                            } header: {
                                Text(dayTitle(section.day))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Ink.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                // Tall enough for a busy week, then it scrolls.
                .frame(height: min(400, CGFloat(lines.count) * 38 + CGFloat(sections.count) * 28 + 12))
            }
        }
        .frame(width: 320)
    }

    private func row(_ line: Line) -> some View {
        let entry = line.entry
        return HStack(spacing: 10) {
            Circle()
                .fill(Palette.color(slot: line.activity.colorSlot))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(line.activity.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail(for: entry))
                    .font(.caption)
                    .foregroundStyle(Ink.muted)
            }

            Spacer(minLength: 8)

            Text(signed(entry.minutes))
                .monospacedDigit()
                .foregroundStyle(entry.minutes < 0 ? Ink.muted : Ink.secondary)

            dayMenu(for: entry)

            Button {
                withAnimation(Motion.snappy) { store.deleteEntry(entry.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(hoveredID == entry.id ? Ink.secondary : Ink.muted.opacity(0.6))
            .help("Delete this entry (⌘Z brings it back)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hoveredID == entry.id ? Color.primary.opacity(0.06) : .clear)
        )
        .onHover { hoveredID = $0 ? entry.id : (hoveredID == entry.id ? nil : hoveredID) }
    }

    /// Moves the entry to another day of its own week. Days still to come are left out:
    /// time can't have been spent on them yet.
    private func dayMenu(for entry: Entry) -> some View {
        let today = WeekMath.startOfDay(Date())
        let days = WeekMath.daysOfWeek(containing: entry.day).filter { $0 <= today }
        return Menu {
            ForEach(days, id: \.self) { day in
                Button {
                    withAnimation(Motion.snappy) { store.moveEntry(entry.id, to: day) }
                } label: {
                    if Calendar.current.isDate(day, inSameDayAs: entry.day) {
                        Label(menuTitle(day), systemImage: "checkmark")
                    } else {
                        Text(menuTitle(day))
                    }
                }
            }
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(hoveredID == entry.id ? Ink.secondary : Ink.muted.opacity(0.6))
        .help("Move this entry to another day")
    }

    private func menuTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    /// When it was added, and anything that sets it apart: a typed-in total, or time
    /// put on a different day from the one it was added on.
    private func detail(for entry: Entry) -> String {
        var parts = [entry.createdAt.formatted(date: .omitted, time: .shortened)]
        if !Calendar.current.isDate(entry.day, inSameDayAs: entry.createdAt) {
            // A weekday alone only says which day within the week it was added in.
            let day = WeekMath.isSameWeek(entry.day, entry.createdAt)
                ? entry.day.formatted(.dateTime.weekday(.wide))
                : entry.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            parts.append("for \(day)")
        }
        if entry.isAdjustment { parts.append("total edited") }
        return parts.joined(separator: " · ")
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func signed(_ minutes: Int) -> String {
        (minutes < 0 ? "−" : "+") + Duration.format(minutes: abs(minutes))
    }
}
