import SwiftUI
import Combine

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(Friends.self) private var friends
    @Environment(Updates.self) private var updates

    /// The week being viewed. Past weeks are fully editable — arrow back and log into them.
    @State private var viewedWeek = WeekMath.weekStart(for: Date())
    /// Today, kept up to date so a window left open overnight moves on with the date.
    @State private var today = WeekMath.startOfDay(Date())
    @State private var hoveredID: UUID?
    /// The group's leaderboard in place of your own chart and rows.
    /// TIMEPIE_SHOW_FRIENDS opens on it, for a test run.
    @State private var showingFriends = ProcessInfo.processInfo.environment["TIMEPIE_SHOW_FRIENDS"] != nil
    /// The log of what's been added this week, dropped down from the toolbar.
    /// TIMEPIE_SHOW_LOG opens on it, for a test run.
    @State private var showingLog = ProcessInfo.processInfo.environment["TIMEPIE_SHOW_LOG"] != nil
    /// Your time over any day, month or interval in place of the week.
    /// TIMEPIE_SHOW_STATS opens on it, for a test run.
    @State private var showingStats = ProcessInfo.processInfo.environment["TIMEPIE_SHOW_STATS"] != nil
    @State private var stats = StatsSelection()
    /// The board everyone can join, for the week on screen.
    /// TIMEPIE_SHOW_GLOBAL opens on it, for a test run.
    @State private var showingGlobal = ProcessInfo.processInfo.environment["TIMEPIE_SHOW_GLOBAL"] != nil
    /// Preferences. TIMEPIE_SHOW_SETTINGS opens on it, for a test run.
    @State private var showingSettings = ProcessInfo.processInfo.environment["TIMEPIE_SHOW_SETTINGS"] != nil
    @AppStorage(Settings.showDayAverage) private var showDayAverage = false
    /// Whether the toolbar's buttons fit side by side or fold into a menu.
    @State private var windowWidth: CGFloat = 560
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The row being dragged by its handle, and how far it has travelled.
    @State private var drag: RowDrag?
    /// One row's height plus the gap below it: how far a row moves per place.
    @State private var rowStride: CGFloat = 30

    /// A running timer. Nothing is logged until you stop it, but the timer itself is
    /// remembered, so quitting or a crash picks it back up still running.
    @State private var running: RunningTimer? = RunningTimer.restore()
    /// Drives the once-a-second redraw while a timer runs.
    @State private var now = Date()
    /// Holds keyboard focus for the ← / → week shortcuts.
    @FocusState private var rootFocused: Bool

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct RunningTimer: Codable, Equatable {
        let activityID: UUID
        let startedAt: Date

        private static let key = "runningTimer"

        static func restore() -> RunningTimer? {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(RunningTimer.self, from: data)
        }

        static func persist(_ timer: RunningTimer?) {
            if let timer, let data = try? JSONEncoder().encode(timer) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private struct RowDrag {
        let id: UUID
        let isFolder: Bool
        /// Its place in the rows when picked up.
        let from: Int
        var offset: CGFloat
        /// Where the gap is, as an index into the rows without the lifted one.
        var slot: Int
        /// A folder the lifted task is held over, to drop it in.
        var into: UUID?
    }

    /// One line in the list as drawn.
    private enum Row: Identifiable {
        case folder(Folder, tasks: [Activity])
        case task(Activity, folder: UUID?)

        var id: UUID {
            switch self {
            case .folder(let folder, _): folder.id
            case .task(let activity, _): activity.id
            }
        }

        /// The folder a task sits in. Nil for folders and loose tasks: the top level.
        var parent: UUID? {
            if case .task(_, let folder) = self { return folder }
            return nil
        }
    }

    private var weekEnd: Date { WeekMath.weekEnd(for: viewedWeek) }
    private var outline: [OutlineItem] { store.outline(forWeek: viewedWeek) }

    /// Every task in the week in list order, hidden ones included — the chart's slices.
    private var activities: [Activity] {
        outline.flatMap { item -> [Activity] in
            switch item {
            case .folder(_, let tasks): tasks
            case .activity(let activity): [activity]
            }
        }
    }

    /// The rows on screen. A collapsed folder's tasks are left out, and so are the
    /// tasks of a folder being dragged — they travel with it.
    private func visibleRows(hidingTasksOf dragged: UUID? = nil) -> [Row] {
        let dragged = dragged ?? drag?.id
        return outline.flatMap { item -> [Row] in
            switch item {
            case .activity(let activity):
                return [.task(activity, folder: nil)]
            case .folder(let folder, let tasks):
                let hidden = folder.collapsed || folder.id == dragged
                return [.folder(folder, tasks: tasks)]
                    + (hidden ? [] : tasks.map { .task($0, folder: folder.id) })
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if showingSettings {
                    SettingsView()
                } else if showingStats {
                    StatsView(selection: $stats)
                } else if showingGlobal {
                    GlobalView(week: viewedWeek)
                } else if showingFriends {
                    FriendsView(week: viewedWeek)
                } else {
                    chart
                    rows
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Clicking the background ends any inline edit: focus goes back to the window.
        .contentShape(Rectangle())
        .onTapGesture { rootFocused = true }
        .environment(\.endEditing) { rootFocused = true }
        // History floats on glass over the bottom of the list, which scrolls under it, and
        // word of a newer version floats in the corner above it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                if let version = updates.available, !updates.dismissed {
                    UpdateNotice(version: version, highlights: updates.highlights) {
                        withAnimation(motion(Motion.snappy)) { updates.dismissed = true }
                    }
                    .padding([.horizontal, .bottom], 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if !showingFriends && !showingStats && !showingGlobal && !showingSettings {
                    HistoryStrip(
                        weeks: historyThumbs(),
                        selectedWeekStart: viewedWeek,
                        onSelect: { select(week: $0) }
                    )
                    .padding([.horizontal, .bottom], 12)
                }
            }
            .animation(motion(Motion.snappy), value: updates.available)
        }
        .frame(minWidth: 460, minHeight: 620)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .navigationTitle(showingStats ? stats.title : WeekMath.weekLabel(for: viewedWeek))
        .navigationSubtitle(shownTotalMinutes == 0
                            ? "Nothing logged"
                            : "\(Duration.format(minutes: shownTotalMinutes)) logged")
        .toolbar { weekToolbar }
        // The pages that take the week's place take turns.
        .modifier(PagesTakeTurns(pages: [$showingStats, $showingFriends, $showingGlobal, $showingSettings]))
        // Every change goes out to the group, if you're in one.
        .onAppear { friends.storeChanged(store, after: 0, force: true) }
        .onChange(of: store.revision) { friends.storeChanged(store) }
        // So does a running timer, renamed or recoloured along with its activity.
        .onChange(of: sharedTimer) { friends.setTimer(sharedTimer) }
        // The leaderboard keeps itself current while it's on screen.
        .task(id: showingFriends) {
            guard showingFriends else { return }
            while !Task.isCancelled {
                await friends.refresh()
                // Often enough to catch a friend starting a timer.
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: running) { RunningTimer.persist(running) }
        // A remembered timer whose activity has since gone is dropped, not resumed.
        .onAppear {
            if let id = running?.activityID, !store.activities.contains(where: { $0.id == id }) {
                running = nil
            }
        }
        .onReceive(tick) { instant in
            // Only redraw while something is actually running.
            if running != nil { now = instant }
            // Checked every tick rather than on a notification, so midnight, waking
            // from sleep and a changed clock or time zone are all caught the same way.
            let day = WeekMath.startOfDay(instant)
            if day != today { dayChanged(to: day) }
        }
        // ← and → step through weeks. Focus lives here only when no text field has it,
        // so arrow keys still move the cursor while you're typing a name or an amount.
        .focusable()
        .focused($rootFocused)
        .focusEffectDisabled()
        .onAppear { rootFocused = true }
        .onKeyPress(.leftArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(1)
            return .handled
        }
    }

    // MARK: - Toolbar

    /// Week navigation lives in the window's toolbar, the way Calendar does it: arrows
    /// on the left beside the week as the window title. On the stats page they step
    /// through days, months or intervals instead. Stats, the log and the group sit on the right.
    @ToolbarContentBuilder
    private var weekToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            let unit = showingStats ? stats.unitName : "Week"
            ControlGroup {
                Button { step(-1) } label: {
                    Label("Previous \(unit)", systemImage: "chevron.left")
                }
                .help("Previous \(unit.lowercased()) (←)")
                Button { step(1) } label: {
                    Label("Next \(unit)", systemImage: "chevron.right")
                }
                .help("Next \(unit.lowercased()) (→)")
            }
            .disabled(showingStats && stats.mode == .allTime)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            // A narrow window can't fit them all, so they fold into one menu.
            if windowWidth < Self.toolbarFoldWidth {
                Menu {
                    pageToggles(anchoringLog: false)
                } label: {
                    Label("Menu", systemImage: "line.3.horizontal")
                }
                .menuIndicator(.hidden)
                .help("Stats, log, friends, leaderboard and settings")
                .popover(isPresented: $showingLog, arrowEdge: .bottom) {
                    LogView(weekStart: viewedWeek)
                }
            } else {
                pageToggles(anchoringLog: true)
                    .labelStyle(.iconOnly)
            }
        }
    }

    /// Below this width the buttons on the right don't all fit beside the week.
    private static let toolbarFoldWidth: CGFloat = 590

    /// The log drops down from its own button, or from the menu when that holds it.
    @ViewBuilder
    private func pageToggles(anchoringLog: Bool) -> some View {
        Toggle(isOn: $showingStats) {
            Label("Stats", systemImage: "calendar")
        }
        .help(showingStats ? "Back to your week" : "Your time over any day, month or interval")
        let log = Toggle(isOn: $showingLog) {
            Label("Log", systemImage: "list.bullet.clipboard")
        }
        .help("Everything logged this week")
        if anchoringLog {
            log.popover(isPresented: $showingLog, arrowEdge: .bottom) {
                LogView(weekStart: viewedWeek)
            }
        } else {
            log
        }
        Toggle(isOn: $showingFriends) {
            Label("Friends", systemImage: "person.2")
        }
        .help(showingFriends ? "Back to your week" : "Compare this week with friends")
        Toggle(isOn: $showingGlobal) {
            Label("Leaderboard", systemImage: "trophy")
        }
        .help(showingGlobal ? "Back to your week" : "This week's totals for everyone using TimePie")
        Toggle(isOn: $showingSettings) {
            Label("Settings", systemImage: "gearshape")
        }
        .help(showingSettings ? "Back to your week" : "Settings")
    }

    // MARK: - Chart

    private var chart: some View {
        DonutChart(slices: slices(), hoveredID: hoveredID, caption: dayAverageCaption,
                   onHover: { hoveredID = $0 })
            .frame(height: 240)
    }

    // MARK: - Rows

    private var rows: some View {
        let rows = visibleRows()
        return VStack(spacing: RowMetrics.spacing) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let isDragged = drag?.id == row.id
                rowView(row, at: index)
                    // Picked up on press: the row rises a touch before it moves.
                    .scaleEffect(isDragged && !reduceMotion ? 1.02 : 1)
                    .animation(motion(Motion.snappy), value: isDragged)
                    // A folder's tasks drop out of it when it opens and fold back up
                    // into it when it closes — the same path both ways.
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
                    .onHover { hoveredID = $0 ? row.id : nil }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        rowStride = $0 + RowMetrics.spacing
                    }
                    .offset(y: displacement(at: index))
                    .zIndex(isDragged ? 1 : 0)
                    // The lifted row tracks the cursor exactly; the others slide aside.
                    .animation(isDragged ? nil : motion(Motion.snappy), value: drag?.slot)
            }

            AddActivityField(
                onAdd: { store.addActivity(named: $0, inWeek: viewedWeek) },
                onAddFolder: { store.addFolder(named: $0, inWeek: viewedWeek) }
            )
        }
        // A tick on the trackpad as the lifted row snaps into each new place, and a
        // firmer one when it's held over a folder it would drop into.
        .sensoryFeedback(.alignment, trigger: drag?.slot) { old, new in old != nil && new != nil }
        .sensoryFeedback(.levelChange, trigger: drag?.into) { _, new in new != nil }
        .padding(6)
        // An inset grouped card, as in System Settings.
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quinary))
    }

    /// While dragging, the highlight stays on the lifted row rather than flickering
    /// across the rows it passes.
    private func isHighlighted(_ id: UUID) -> Bool {
        drag.map { $0.id == id } ?? (hoveredID == id)
    }

    @ViewBuilder
    private func rowView(_ row: Row, at index: Int) -> some View {
        switch row {
        case .folder(let folder, let tasks):
            FolderRow(
                name: folder.name,
                taskCount: tasks.count,
                minutes: tasks.reduce(0) { $0 + max(0, minutes(for: $1)) },
                isCollapsed: folder.collapsed,
                isHovered: isHighlighted(folder.id),
                isDragging: drag?.id == folder.id,
                isDropTarget: drag?.into == folder.id,
                runningSeconds: folder.collapsed
                    ? tasks.first { $0.id == running?.activityID }.map { elapsedSeconds(for: $0.id) }
                    : nil,
                onToggle: {
                    withAnimation(motion(Motion.snappy)) {
                        store.setCollapsed(folder.id, !folder.collapsed)
                    }
                },
                onRename: { store.renameFolder(folder.id, to: $0) },
                onDelete: { withAnimation(motion(Motion.snappy)) { store.deleteFolder(folder.id) } },
                onDragChanged: { dragRow(folder.id, isFolder: true, at: index, by: $0) },
                onDragEnded: endDrag
            )
        case .task(let activity, let folder):
            ActivityRow(
                name: activity.name,
                colorSlot: activity.colorSlot,
                minutes: minutes(for: activity),
                isHovered: isHighlighted(activity.id),
                isDragging: drag?.id == activity.id,
                // A lifted task shows the line when it would land in a folder.
                inFolder: (drag?.id == activity.id
                           ? drag.flatMap { dropTarget(of: $0).parent }
                           : folder) != nil,
                isRunning: running?.activityID == activity.id,
                elapsedSeconds: elapsedSeconds(for: activity.id),
                takenSlots: Set(activities.map(\.colorSlot)),
                onAdd: { minutes in
                    withAnimation(motion(Motion.snappy)) {
                        store.add(minutes: minutes, to: activity.id, on: loggingDay)
                    }
                },
                onSetTotal: {
                    store.setTotal($0, for: activity.id,
                                   weekStart: viewedWeek, weekEnd: weekEnd, on: loggingDay)
                },
                onToggleTimer: { toggleTimer(for: activity) },
                onSetColor: { store.setColor(activity.id, to: $0) },
                onRename: { store.rename(activity.id, to: $0) },
                onDelete: {
                    // Don't leave a timer running against something that's gone.
                    if running?.activityID == activity.id { running = nil }
                    store.delete(activity.id, fromWeek: viewedWeek)
                },
                onDragChanged: { dragRow(activity.id, isFolder: false, at: index, by: $0) },
                onDragEnded: endDrag
            )
        }
    }

    // MARK: - Reordering

    private func dragRow(_ id: UUID, isFolder: Bool, at index: Int, by translation: CGFloat) {
        var lifted = drag ?? RowDrag(id: id, isFolder: isFolder, from: index,
                                     offset: 0, slot: index, into: nil)
        let others = visibleRows(hidingTasksOf: id).filter { $0.id != id }
        let lowest = -CGFloat(lifted.from) * rowStride
        let highest = CGFloat(others.count - lifted.from) * rowStride
        lifted.offset = rubberBand(translation, lower: lowest, upper: highest)
        settle(&lifted, among: others)
        drag = lifted
    }

    /// Past either end of the list the row follows less and less instead of stopping
    /// dead, so the list reads as having an edge rather than freezing. It springs back
    /// on release.
    private func rubberBand(_ x: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        let span = rowStride * 2
        let c: CGFloat = 0.55
        func resist(_ over: CGFloat) -> CGFloat { over * span * c / (span + c * over) }
        if x < lower { return lower - resist(lower - x) }
        if x > upper { return upper + resist(x - upper) }
        return x
    }

    /// The spring to use, or a plain cross-fade under Reduce Motion.
    private func motion(_ spring: Animation) -> Animation {
        reduceMotion ? Motion.reduced : spring
    }

    /// Moves the gap to follow the lifted row, a place at a time once it covers more
    /// than half of its neighbour. A task passing over a folder pauses there instead:
    /// held over the middle of the folder's row, it would drop into the folder.
    private func settle(_ lifted: inout RowDrag, among others: [Row]) {
        // The lifted row's top edge, in rows.
        let top = lifted.offset / rowStride + CGFloat(lifted.from)
        lifted.into = nil
        while true {
            let down = top > CGFloat(lifted.slot)
            let overlap = abs(top - CGFloat(lifted.slot))
            let neighbour = down ? lifted.slot : lifted.slot - 1
            guard others.indices.contains(neighbour) else { return }

            if !lifted.isFolder, case .folder(let folder, _) = others[neighbour] {
                if overlap > 0.7 {
                    lifted.slot += down ? 1 : -1
                    continue
                }
                if overlap >= 0.3 { lifted.into = folder.id }
                return
            }
            guard overlap > 0.5 else { return }
            lifted.slot += down ? 1 : -1
        }
    }

    /// How far a row is pushed to open the gap; the lifted row follows the cursor.
    private func displacement(at index: Int) -> CGFloat {
        guard let drag else { return 0 }
        if index == drag.from { return drag.offset }
        let k = index < drag.from ? index : index - 1
        let shown = k < drag.slot ? k : k + 1
        return CGFloat(shown - index) * rowStride
    }

    /// Where the lifted row would land: in a folder or at the top level (nil), and
    /// its place among what this week shows there.
    private func dropTarget(of lifted: RowDrag) -> (parent: UUID?, index: Int) {
        if let into = lifted.into { return (into, .max) }
        let others = visibleRows(hidingTasksOf: lifted.id).filter { $0.id != lifted.id }
        let before = others.prefix(lifted.slot)
        let topLevel = before.filter { $0.parent == nil }.count
        // Folders don't nest; one dropped among a folder's tasks lands after it.
        if lifted.isFolder { return (nil, topLevel) }
        // Between two of a folder's tasks, or above its first: in that folder.
        if lifted.slot < others.count, let folder = others[lifted.slot].parent {
            return (folder, before.filter { $0.parent == folder }.count)
        }
        // Straight under an open folder that has nothing else in it.
        if case .folder(let folder, _)? = before.last, !folder.collapsed {
            return (folder.id, 0)
        }
        return (nil, topLevel)
    }

    private func endDrag() {
        guard let finished = drag else { return }
        let target = dropTarget(of: finished)
        // Moving the row and clearing its offset in one animated step means the
        // rows that slid aside stay put; only the lifted one settles into its slot.
        withAnimation(motion(Motion.settle)) {
            store.move(finished.id, into: target.parent, at: target.index, inWeek: viewedWeek)
            drag = nil
        }
    }

    // MARK: - The timer

    private func toggleTimer(for activity: Activity) {
        if running?.activityID == activity.id {
            stopTimer()
        } else {
            // One timer at a time: starting a new one logs and closes the old.
            stopTimer()
            now = Date()
            running = RunningTimer(activityID: activity.id, startedAt: now)
        }
    }

    private func stopTimer() {
        guard let timer = running else { return }
        running = nil
        store.logSession(timer.activityID, from: timer.startedAt, to: Date())
    }

    /// The running timer as the group sees it.
    private var sharedTimer: Friends.MyTimer? {
        guard let timer = running,
              let activity = store.activities.first(where: { $0.id == timer.activityID }) else { return nil }
        return Friends.MyTimer(name: activity.name, colorSlot: activity.colorSlot, startedAt: timer.startedAt)
    }

    private func elapsedSeconds(for id: UUID) -> Int {
        guard let timer = running, timer.activityID == id else { return 0 }
        return max(0, Int(now.timeIntervalSince(timer.startedAt)))
    }

    // MARK: - Derived data

    /// Logged time only. A running session stays out of the chart and the totals until
    /// it's stopped, then lands in one animated step — the row's stopwatch is where
    /// it counts up in the meantime.
    private func minutes(for activity: Activity) -> Int {
        store.minutes(activityID: activity.id, from: viewedWeek, to: weekEnd)
    }

    private var weekTotalMinutes: Int {
        store.totalMinutes(from: viewedWeek, to: weekEnd)
    }

    /// "~3,5h": the week's total spread over its days so far, if that's switched on.
    private var dayAverageCaption: String? {
        guard showDayAverage, weekTotalMinutes > 0 else { return nil }
        let days = WeekMath.daysElapsed(inWeek: viewedWeek, today: today)
        guard days > 0 else { return nil }
        return Duration.approxHours(minutes: Double(weekTotalMinutes) / Double(days))
    }

    /// The total in the window's subtitle: the week's, or the stats page's span.
    private var shownTotalMinutes: Int {
        showingStats
            ? store.totalMinutes(from: stats.start, to: stats.endExclusive)
            : weekTotalMinutes
    }

    /// Every activity, not just this week's: the chart keeps the same slices from week
    /// to week (the ones without time there are empty), so flipping weeks animates.
    private func slices() -> [Slice] {
        store.orderedActivities.map {
            Slice(id: $0.id, name: $0.name,
                  minutes: max(0, minutes(for: $0)), colorSlot: $0.colorSlot)
        }
    }

    private func historyThumbs() -> [HistoryStrip.WeekThumb] {
        let thisWeek = WeekMath.weekStart(for: today)
        return (-11...0).map { offset in
            let start = WeekMath.addWeeks(offset, to: thisWeek)
            let end = WeekMath.weekEnd(for: start)
            let slices = store.activities(forWeek: start).compactMap { activity -> Slice? in
                let mins = store.minutes(activityID: activity.id, from: start, to: end)
                guard mins > 0 else { return nil }
                return Slice(id: activity.id, name: activity.name,
                             minutes: mins, colorSlot: activity.colorSlot)
            }
            return HistoryStrip.WeekThumb(
                id: start,
                slices: slices,
                totalMinutes: store.totalMinutes(from: start, to: end),
                label: WeekMath.weekLabel(for: start)
            )
        }
    }

    // MARK: - Navigation

    /// ← / →: a week, or on the stats page whatever span it shows.
    private func step(_ n: Int) {
        if showingStats {
            withAnimation(motion(Motion.snappy)) { stats.step(n) }
        } else {
            select(week: WeekMath.addWeeks(n, to: viewedWeek))
        }
    }

    private func select(week: Date) {
        viewedWeek = WeekMath.weekStart(for: week)
    }

    /// The day a click attributes to: today in this week, the Monday of any other.
    /// Worked out at the moment of the click, so it can never be left behind on a
    /// day that has passed.
    private var loggingDay: Date {
        let now = Date()
        return WeekMath.isSameWeek(viewedWeek, now) ? WeekMath.startOfDay(now) : viewedWeek
    }

    /// Whatever was showing the old today follows on to the new one: this week moves
    /// to the next on Monday, and an untouched stats page to the new day. A week or
    /// day you went back to on purpose stays where you put it.
    private func dayChanged(to day: Date) {
        let previous = today
        today = day
        if viewedWeek == WeekMath.weekStart(for: previous) { select(week: day) }
        if stats == StatsSelection(today: previous) { stats = StatsSelection(today: day) }
    }
}

/// Turning one page on turns the others off.
private struct PagesTakeTurns: ViewModifier {
    let pages: [Binding<Bool>]

    func body(content: Content) -> some View {
        content.onChange(of: pages.map(\.wrappedValue)) { old, new in
            guard let opened = new.indices.first(where: { new[$0] && !old[$0] }) else { return }
            for i in pages.indices where i != opened { pages[i].wrappedValue = false }
        }
    }
}
