import Foundation
import Observation

/// Everything lives in one human-readable JSON file.
///
/// ~/Library/Application Support/TimePie/timepie.json
///
/// A personal tracker accumulates a few thousand entries over years, so the whole
/// file is held in memory and rewritten atomically on every change. That keeps the
/// model honest and the file readable, which matters more here than write amplification.
@Observable
final class Store {
    private(set) var activities: [Activity] = []
    private(set) var entries: [Entry] = []
    private(set) var folders: [Folder] = []
    /// Goes up by one on every save, for anything that needs to follow changes.
    private(set) var revision = 0

    private let fileURL: URL
    /// ⌘Z restores the previous state. Snapshots are uniform across every kind of
    /// edit — add, adjust, rename, archive — so undo never has to know what it is undoing.
    private var undoStack: [Payload] = []
    private let undoLimit = 50

    var canUndo: Bool { !undoStack.isEmpty }

    // MARK: - Lifecycle

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Store.defaultFileURL()
        load()
    }

    static func defaultFileURL() -> URL {
        // Lets a test run point at throwaway data, as the Windows build does.
        if let dir = ProcessInfo.processInfo.environment["TIMEPIE_DATA_DIR"] {
            return URL(fileURLWithPath: dir).appendingPathComponent("timepie.json")
        }
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = base.appendingPathComponent("TimePie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("timepie.json")
    }

    var storeLocation: URL { fileURL }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? Store.decoder().decode(Payload.self, from: data)
        else { return }
        activities = payload.activities
        entries = payload.entries
        folders = payload.folders

        // One-time cleanup. "Delete" used to mean "archive", which hid the activity from
        // the rows while its time still counted toward the header total and the history
        // thumbnails — the source of the 4h-vs-2h mismatch. Deleting now removes the
        // entries too, so anything already archived is purged here.
        let archived = Set(activities.filter(\.archived).map(\.id))
        if !archived.isEmpty {
            activities.removeAll { archived.contains($0.id) }
            entries.removeAll { archived.contains($0.activityID) }
            save()
        }
    }

    var payload: Payload {
        Payload(activities: activities, entries: entries, folders: folders)
    }

    private func save() {
        revision += 1
        guard let data = try? Store.encoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Snapshot, mutate, persist — the single path every edit takes.
    private func mutate(_ block: () -> Void) {
        undoStack.append(payload)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        block()
        save()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        activities = previous.activities
        entries = previous.entries
        // Showing or hiding a folder's tasks isn't an edit, so undo leaves it alone.
        let collapsed = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.collapsed) })
        folders = previous.folders.map { folder in
            var folder = folder
            folder.collapsed = collapsed[folder.id] ?? folder.collapsed
            return folder
        }
        save()
    }

    // MARK: - Reading

    var visibleActivities: [Activity] {
        activities.filter { !$0.archived }.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// The list for one week: everything started on or before it, plus anything with
    /// time logged in it — so older weeks never lose a row that holds their hours.
    /// Activities deleted in this week or an earlier one are left out.
    func activities(forWeek weekStart: Date) -> [Activity] {
        let end = WeekMath.weekEnd(for: weekStart)
        let logged = Set(entries(from: weekStart, to: end).map(\.activityID))
        return visibleActivities.filter {
            if let ended = $0.endWeekStart, ended <= weekStart { return false }
            return $0.firstWeekStart <= weekStart || logged.contains($0.id)
        }
    }

    /// The week's list as drawn: folders and loose tasks in order, each folder with the
    /// tasks it holds that week. A folder shows from the week it was made, and in any
    /// earlier week that has one of its tasks.
    func outline(forWeek weekStart: Date) -> [OutlineItem] {
        let tasks = activities(forWeek: weekStart)
        let known = Set(folders.map(\.id))
        let shown = folders.filter { folder in
            folder.firstWeekStart <= weekStart || tasks.contains { $0.folderID == folder.id }
        }
        let items = shown.map { folder in
            (folder.sortIndex, OutlineItem.folder(folder, tasks.filter { $0.folderID == folder.id }))
        } + tasks.filter { !known.contains($0.folderID ?? UUID()) }.map {
            ($0.sortIndex, OutlineItem.activity($0))
        }
        return items.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Every task in the order the lists draw them, ignoring weeks: each week's list is
    /// this order with some rows left out.
    var orderedActivities: [Activity] {
        let tasks = visibleActivities
        let known = Set(folders.map(\.id))
        let items = folders.map { folder in
            (folder.sortIndex, tasks.filter { $0.folderID == folder.id })
        } + tasks.filter { !known.contains($0.folderID ?? UUID()) }.map {
            ($0.sortIndex, [$0])
        }
        return items.sorted { $0.0 < $1.0 }.flatMap(\.1)
    }

    /// One group of siblings in order: the top level (folders and loose tasks) when
    /// `parent` is nil, otherwise that folder's tasks. With a week, only what it shows.
    private func siblings(in parent: UUID?, week: Date?) -> [UUID] {
        if let week {
            let items = outline(forWeek: week)
            guard let parent else { return items.map(\.id) }
            for case let .folder(folder, tasks) in items where folder.id == parent {
                return tasks.map(\.id)
            }
            return []
        }
        if let parent {
            return visibleActivities.filter { $0.folderID == parent }.map(\.id)
        }
        let known = Set(folders.map(\.id))
        let loose = visibleActivities.filter { !known.contains($0.folderID ?? UUID()) }
        return (folders.map { ($0.sortIndex, $0.id) } + loose.map { ($0.sortIndex, $0.id) })
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    func entries(from start: Date, to end: Date) -> [Entry] {
        entries.filter { $0.day >= start && $0.day < end }
    }

    func minutes(activityID: UUID, from start: Date, to end: Date) -> Int {
        entries(from: start, to: end)
            .filter { $0.activityID == activityID }
            .reduce(0) { $0 + $1.minutes }
    }

    /// Every activity's time between two days, in one pass over the entries.
    func minutesByActivity(from start: Date, to end: Date) -> [UUID: Int] {
        entries(from: start, to: end).reduce(into: [:]) { $0[$1.activityID, default: 0] += $1.minutes }
    }

    /// Each day's time between two days, keyed by start of day.
    func minutesByDay(from start: Date, to end: Date) -> [Date: Int] {
        let known = Set(activities.map(\.id))
        return entries(from: start, to: end)
            .filter { known.contains($0.activityID) }
            .reduce(into: [:]) { $0[$1.day, default: 0] += $1.minutes }
    }

    /// The first and last day anything was logged on, or nil before anything has been.
    var loggedSpan: ClosedRange<Date>? {
        guard let first = entries.map(\.day).min(), let last = entries.map(\.day).max() else { return nil }
        return first...last
    }

    /// Counts only entries belonging to an activity that still exists, so the header
    /// total can never disagree with the sum of the donut's wedges.
    func totalMinutes(from start: Date, to end: Date) -> Int {
        let known = Set(activities.map(\.id))
        return max(0, entries(from: start, to: end)
            .filter { known.contains($0.activityID) }
            .reduce(0) { $0 + $1.minutes })
    }

    // MARK: - Writing

    func add(minutes: Int, to activityID: UUID, on day: Date) {
        mutate {
            entries.append(Entry(activityID: activityID,
                                 day: WeekMath.startOfDay(day),
                                 minutes: minutes))
        }
    }

    /// A timer session, split at each midnight it ran past: 23:00 to 01:00 is an hour
    /// on each day, and a session over Sunday night counts toward both weeks. The pieces
    /// are rounded so they always add up to the session's rounded length.
    func logSession(_ activityID: UUID, from start: Date, to end: Date) {
        var pieces: [(day: Date, minutes: Int)] = []
        var dayStart = start
        var loggedSoFar = 0
        while dayStart < end {
            let nextDay = WeekMath.addDays(1, to: WeekMath.startOfDay(dayStart))
            let upTo = min(nextDay, end)
            let total = Int((upTo.timeIntervalSince(start) / 60).rounded())
            if total > loggedSoFar {
                pieces.append((WeekMath.startOfDay(dayStart), total - loggedSoFar))
                loggedSoFar = total
            }
            dayStart = upTo
        }
        // Anything under half a minute rounds to nothing and isn't worth an entry.
        guard !pieces.isEmpty else { return }
        mutate {
            for piece in pieces {
                entries.append(Entry(activityID: activityID, day: piece.day, minutes: piece.minutes))
            }
        }
    }

    /// The typed value is a week *total*; the difference is written as adjustments.
    /// Time added goes on the logging day. Time taken away takes back the most recently
    /// logged time first — lowering a total is nearly always correcting something you
    /// just did, like a click too many or a timer left running — and never takes a day
    /// below zero.
    func setTotal(_ target: Int, for activityID: UUID,
                  weekStart: Date, weekEnd: Date, on day: Date) {
        let current = minutes(activityID: activityID, from: weekStart, to: weekEnd)
        let delta = max(0, target) - current
        guard delta != 0 else { return }
        var changes = [(day: WeekMath.startOfDay(day), minutes: delta)]
        if delta < 0 {
            let logged = entries(from: weekStart, to: weekEnd).filter { $0.activityID == activityID }
            var byDay = logged.reduce(into: [Date: Int]()) { $0[$1.day, default: 0] += $1.minutes }
            var taken: [Date: Int] = [:]
            var left = -delta
            // Saved times only keep whole seconds, so ties (a session's pieces, quick
            // clicks) go by the order they were logged in.
            let newestFirst = logged.enumerated()
                .sorted { ($0.element.createdAt, $0.offset) > ($1.element.createdAt, $1.offset) }
                .map(\.element)
            for entry in newestFirst where left > 0 && entry.minutes > 0 {
                let take = min(entry.minutes, byDay[entry.day, default: 0], left)
                guard take > 0 else { continue }
                taken[entry.day, default: 0] += take
                byDay[entry.day, default: 0] -= take
                left -= take
            }
            changes = taken.sorted { $0.key < $1.key }.map { ($0.key, -$0.value) }
        }
        mutate {
            for change in changes {
                entries.append(Entry(activityID: activityID, day: change.day,
                                     minutes: change.minutes, isAdjustment: true))
            }
        }
    }

    /// Takes back one logged amount, from the log.
    func deleteEntry(_ id: UUID) {
        deleteEntries([id])
    }

    /// Several at once, as one step for ⌘Z.
    func deleteEntries(_ ids: Set<UUID>) {
        guard entries.contains(where: { ids.contains($0.id) }) else { return }
        mutate { entries.removeAll { ids.contains($0.id) } }
    }

    /// Puts an entry on another day, for time added on the day it was typed in that
    /// belongs to an earlier one. Only the day changes; when it was added stays.
    func moveEntries(_ ids: Set<UUID>, to day: Date) {
        let day = WeekMath.startOfDay(day)
        guard entries.contains(where: { ids.contains($0.id) && $0.day != day }) else { return }
        mutate {
            for index in entries.indices where ids.contains(entries[index].id) {
                entries[index].day = day
            }
        }
    }

    func addActivity(named name: String, inWeek weekStart: Date) {
        mutate {
            // Only colours on screen in this week are off the table, so older, unrelated
            // activities don't use up the eight slots forever.
            let taken = activities(forWeek: weekStart).map(\.colorSlot)
            activities.append(Activity(
                name: name,
                colorSlot: Palette.nextSlot(taken: taken),
                sortIndex: nextSortIndex,
                firstWeek: DayStamp.string(from: WeekMath.weekStart(for: weekStart))
            ))
        }
    }

    /// New things go to the bottom of the list.
    private var nextSortIndex: Int {
        ((activities.map(\.sortIndex) + folders.map(\.sortIndex)).max() ?? -1) + 1
    }

    func addFolder(named name: String, inWeek weekStart: Date) {
        mutate {
            folders.append(Folder(
                name: name,
                sortIndex: nextSortIndex,
                firstWeek: DayStamp.string(from: WeekMath.weekStart(for: weekStart))
            ))
        }
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        mutate { folders[i].name = name }
    }

    /// Hiding or showing a folder's tasks is a view preference, so it skips undo.
    func setCollapsed(_ id: UUID, _ collapsed: Bool) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].collapsed = collapsed
        save()
    }

    /// Deleting a folder keeps its tasks: they move out to the top level, in its place.
    func deleteFolder(_ id: UUID) {
        guard folders.contains(where: { $0.id == id }) else { return }
        let tasks = siblings(in: id, week: nil)
        var top = siblings(in: nil, week: nil)
        if let i = top.firstIndex(of: id) { top.replaceSubrange(i...i, with: tasks) }
        mutate {
            folders.removeAll { $0.id == id }
            for i in activities.indices where activities[i].folderID == id {
                activities[i].folderID = nil
            }
            renumber(top)
        }
    }

    /// Colour follows the entity, so changing it is an explicit act — never something
    /// that happens because an activity's rank or position changed.
    func setColor(_ id: UUID, to slot: Int) {
        guard let i = activities.firstIndex(where: { $0.id == id }) else { return }
        mutate { activities[i].colorSlot = slot }
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = activities.firstIndex(where: { $0.id == id }) else { return }
        mutate { activities[i].name = name }
    }

    /// Deleting from a week removes the activity from that week and every later one,
    /// along with the time logged there. Earlier weeks keep the row and their hours.
    /// If no earlier week ever showed it, nothing is worth keeping and it goes entirely.
    /// ⌘Z restores all of it, since `mutate` snapshots the whole payload first.
    func delete(_ id: UUID, fromWeek weekStart: Date) {
        guard let i = activities.firstIndex(where: { $0.id == id }) else { return }
        let start = WeekMath.weekStart(for: weekStart)
        let shownEarlier = activities[i].firstWeekStart < start
            || entries.contains { $0.activityID == id && $0.day < start }
        mutate {
            entries.removeAll { $0.activityID == id && $0.day >= start }
            if shownEarlier {
                activities[i].endWeek = DayStamp.string(from: start)
            } else {
                activities.remove(at: i)
            }
        }
    }

    /// Moves a task or folder to `index` among what this week shows in `parent` — a
    /// folder, or nil for the top level. Folders only live at the top level.
    ///
    /// There is a single order shared by every week, so the item is placed beside the
    /// same neighbour in the full list. Items this week doesn't show keep their places.
    func move(_ id: UUID, into parent: UUID?, at index: Int, inWeek weekStart: Date) {
        let isFolder = folders.contains { $0.id == id }
        guard isFolder || activities.contains(where: { $0.id == id }) else { return }
        let parent = isFolder ? nil : parent

        let shown = siblings(in: parent, week: weekStart).filter { $0 != id }
        var all = siblings(in: parent, week: nil).filter { $0 != id }
        let k = min(max(index, 0), shown.count)
        let at = k < shown.count
            ? all.firstIndex(of: shown[k]) ?? all.count
            : shown.last.flatMap { all.firstIndex(of: $0) }.map { $0 + 1 } ?? all.count
        all.insert(id, at: at)

        let currentParent = activities.first { $0.id == id }?.folderID
        guard currentParent != parent || all != siblings(in: parent, week: nil) else { return }
        mutate {
            if let i = activities.firstIndex(where: { $0.id == id }) {
                activities[i].folderID = parent
            }
            renumber(all)
        }
    }

    /// Sort indices only matter among siblings, so one group is renumbered at a time.
    private func renumber(_ ids: [UUID]) {
        for (n, id) in ids.enumerated() {
            if let i = activities.firstIndex(where: { $0.id == id }) {
                activities[i].sortIndex = n
            } else if let i = folders.firstIndex(where: { $0.id == id }) {
                folders[i].sortIndex = n
            }
        }
    }
}
