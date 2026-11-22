import AppKit
import SwiftUI

/// One activity: identity carried by the colour dot, everything else in ink.
///
/// Laid out as three zones — name, total, controls. The outer two both expand
/// equally, so the fixed-width total column lands dead centre of the window and
/// stays aligned across every row regardless of how long the names are.
struct ActivityRow: View {
    let name: String
    let colorSlot: Int
    let minutes: Int
    let isHovered: Bool
    /// Lifted off the list while its handle is being dragged.
    let isDragging: Bool
    /// Sits in a folder: indented, with the folder's line running down its left.
    let inFolder: Bool

    /// Live timer state. It lives only as long as the app does, so nothing here is persisted.
    let isRunning: Bool
    let elapsedSeconds: Int

    /// Slots already in use, so the picker can mark them rather than silently letting
    /// two activities wear the same colour.
    let takenSlots: Set<Int>

    let onAdd: (Int) -> Void
    /// The typed value is the activity's *week total*; the caller writes the difference.
    let onSetTotal: (Int) -> Void
    let onToggleTimer: () -> Void
    let onSetColor: (Int) -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    /// Vertical distance the handle has been dragged since it was pressed.
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var editingHours = false
    @State private var hoursDraft = ""
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var pickingColor = false
    @State private var showingColorWindow = false
    @FocusState private var hoursFocused: Bool
    @FocusState private var nameFocused: Bool
    @Environment(\.endEditing) private var endEditing

    var body: some View {
        HStack(spacing: 10) {
            nameZone
                .frame(maxWidth: .infinity, alignment: .leading)

            totalZone
                .frame(width: RowMetrics.totalColumnWidth)

            controlZone
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .overlay(alignment: .leading) {
            if inFolder {
                Rectangle()
                    .fill(Ink.muted.opacity(0.45))
                    .frame(width: 1)
                    // A point past the row's edges into the gaps on either side, so the
                    // line runs unbroken through every task in the folder.
                    .padding(.vertical, -RowMetrics.spacing / 2)
                    .padding(.leading, 8 + RowMetrics.folderLineX)
            }
        }
        .rowChrome(isHovered: isHovered, isDragging: isDragging)
        // Double-click anywhere on the row to start or stop its timer. Renaming moved
        // to the right-click menu because the old double-click-the-name gesture would
        // have collided with this one.
        //
        // This is a single-tap gesture that reads AppKit's click count rather than
        // `onTapGesture(count: 2)`: a double-tap gesture on the row makes every button
        // inside it wait out the double-click interval before it fires.
        .contentShape(Rectangle())
        .onTapGesture {
            if NSApp.currentEvent?.clickCount == 2 {
                onToggleTimer()
            } else if !editingHours && !editingName {
                // Guarded so a click into this row's own field can't close it.
                endEditing()
            }
        }
        .help(isRunning ? "Double-click to stop" : "Double-click to start a timer")
        .contextMenu {
            Button("Rename…") { nameDraft = name; editingName = true }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    // MARK: - Zones

    private var nameZone: some View {
        HStack(spacing: 10) {
            Button { pickingColor = true } label: {
                Circle()
                    .fill(Palette.color(slot: colorSlot))
                    .frame(width: 11, height: 11)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change colour")
            .popover(isPresented: $pickingColor, arrowEdge: .bottom) {
                ColorSwatchPicker(current: colorSlot, taken: takenSlots, onPick: { slot in
                    onSetColor(slot)
                    pickingColor = false
                }, onMore: {
                    pickingColor = false
                    // Let the popover finish closing before the sheet slides down.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showingColorWindow = true
                    }
                })
            }
            .sheet(isPresented: $showingColorWindow) {
                ColorWindow(initialSlot: colorSlot, taken: takenSlots, onDone: { slot in
                    onSetColor(slot)
                    showingColorWindow = false
                }, onCancel: {
                    showingColorWindow = false
                })
            }

            if editingName {
                TextField("", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .focused($nameFocused)
                    .onAppear { nameFocused = true }
                    .onSubmit(commitName)
                    .onExitCommand { editingName = false }
                    // Clicking anywhere else keeps what was typed, like renaming in Finder.
                    .onChange(of: nameFocused) { _, focused in
                        if !focused && editingName { commitName() }
                    }
            } else {
                Text(name)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // The running session, counting up. It lives in this zone so that starting
            // a timer never shifts the total column.
            if isRunning {
                Text(Duration.clock(seconds: elapsedSeconds))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Ink.secondary)
            }
        }
        .padding(.leading, inFolder ? RowMetrics.folderIndent : 0)
    }

    @ViewBuilder
    private var totalZone: some View {
        if editingHours {
            TextField("", text: $hoursDraft)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .focused($hoursFocused)
                .onAppear { hoursFocused = true }
                .onSubmit(commitHours)
                .onExitCommand { editingHours = false }
                // Clicking anywhere else keeps what was typed; Escape throws it away.
                .onChange(of: hoursFocused) { _, focused in
                    if !focused && editingHours { commitHours() }
                }
        } else {
            Text(Duration.format(minutes: minutes))
                .monospacedDigit()
                // Rolls to the new value when time is added, so the click visibly lands.
                .contentTransition(.numericText(value: Double(minutes)))
                .foregroundStyle(minutes == 0 ? Ink.muted : Ink.secondary)
                .frame(maxWidth: .infinity, minHeight: 22)
                // Without this the number gives no sign it can be typed into.
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? Color.primary.opacity(0.09) : .clear)
                )
                .contentShape(Rectangle())
                // Claimed here so a click on the total edits it instead of falling
                // through to the row's start/stop-the-timer gesture.
                .onTapGesture { beginEditingHours() }
                .help("Click to type this week's total — 1h45, 90, 1.5h, 2h")
        }
    }

    private var controlZone: some View {
        HStack(spacing: 6) {
            Button(action: onToggleTimer) {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isRunning ? Palette.color(slot: colorSlot) : Ink.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isRunning ? "Stop and log this session" : "Start a timer")

            Group {
                Button("+30m") { onAdd(30) }
                Button("+1h") { onAdd(60) }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            DragHandle(isDragging: isDragging, onChanged: onDragChanged, onEnded: onDragEnded)
        }
    }

    // MARK: - Commits

    private func beginEditingHours() {
        hoursDraft = minutes == 0 ? "" : Duration.format(minutes: minutes)
        editingHours = true
    }

    private func commitHours() {
        if let mins = Duration.parse(hoursDraft) { onSetTotal(mins) }
        editingHours = false
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { onRename(trimmed) }
        editingName = false
    }
}

private struct EndEditingKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Ends whatever inline edit is open by handing keyboard focus back to the window.
    /// Rows call it on a plain click, so clicking a row works like clicking the background.
    var endEditing: () -> Void {
        get { self[EndEditingKey.self] }
        set { self[EndEditingKey.self] = newValue }
    }
}

/// Shared by task and folder rows so the columns line up.
enum RowMetrics {
    static let totalColumnWidth: CGFloat = 96
    static let spacing: CGFloat = 2
    /// How far a folder's tasks sit in from the left, and where its line runs.
    static let folderIndent: CGFloat = 16
    static let folderLineX: CGFloat = 5
}

extension View {
    /// The hover tint, and the lifted look while the row is being dragged.
    func rowChrome(isHovered: Bool, isDragging: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        // While lifted, an opaque backing hides the rows it passes over.
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Ink.raised)
                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                .opacity(isDragging ? 1 : 0)
        )
    }
}

/// Three dots stacked vertically. Press and hold to drag the row up or down.
struct DragHandle: View {
    let isDragging: Bool
    /// Vertical distance travelled since the handle was pressed.
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        VStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().frame(width: 3, height: 3)
            }
        }
        .foregroundStyle(isDragging ? Ink.secondary : Ink.muted)
        .frame(width: 14, height: 22)
        .contentShape(Rectangle())
        .modifier(GrabCursor(active: isDragging))
        // Measured in the window's space: the handle moves with the row, so its own
        // coordinates would shift under the cursor while dragging.
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { onChanged($0.translation.height) }
                .onEnded { _ in onEnded() }
        )
        .help("Drag to reorder")
    }
}

/// An open hand over the handle, closed while dragging. The pointer API is macOS 15+.
private struct GrabCursor: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(active ? .grabActive : .grabIdle)
        } else {
            content
        }
    }
}

/// The eight validated palette slots plus the neutral overflow, as pickable swatches,
/// then recent custom colours and the way into the full colour window.
struct ColorSwatchPicker: View {
    let current: Int
    let taken: Set<Int>
    let onPick: (Int) -> Void
    let onMore: () -> Void

    /// Recent custom colours, with this activity's own first if it has one.
    private var customs: [Int] {
        let recents = CustomColors.recents
        guard Palette.isCustom(current), !recents.contains(current) else { return recents }
        return Array(([current] + recents).prefix(CustomColors.limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour")
                .font(.system(size: 11))
                .foregroundStyle(Ink.muted)

            HStack(spacing: 8) {
                ForEach(0...Palette.slotCount, id: \.self) { slot in
                    swatch(slot)
                }
            }

            if !customs.isEmpty {
                HStack(spacing: 8) {
                    ForEach(customs, id: \.self) { slot in
                        swatch(slot)
                    }
                }
            }

            Text("A dot marks a colour another activity already uses.")
                .font(.system(size: 10))
                .foregroundStyle(Ink.muted)

            Divider()

            Button(action: onMore) {
                Label("More Colours…", systemImage: "paintpalette")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.primary)
            .help("Pick any colour from a grid, a spectrum or sliders")
        }
        .padding(12)
    }

    private func swatch(_ slot: Int) -> some View {
        Swatch(slot: slot, isCurrent: slot == current, isTaken: taken.contains(slot),
               help: slot == Palette.slotCount ? "Neutral grey (past the eight-colour palette)"
                   : Palette.isCustom(slot) ? "Custom colour \(HSV.hex(Palette.rgb(slot: slot)))"
                   : "Palette colour \(slot + 1)") {
            onPick(slot)
        }
    }
}

/// The inline `+` below the rows — a field you type into, never a dialog. The folder
/// button at its right end opens the same field for naming a new folder.
struct AddActivityField: View {
    let onAdd: (String) -> Void
    let onAddFolder: (String) -> Void

    private enum Mode { case activity, folder }
    @State private var mode: Mode?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mode == .folder ? "folder.fill.badge.plus" : "plus.circle.fill")
                .font(.system(size: 15))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 17)

            if let mode {
                TextField(mode == .folder ? "New folder" : "New activity", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { collapse() }
                    // Clicking away from an empty field closes it; typed text is kept.
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused && draft.isEmpty { collapse() }
                    }
            } else {
                Text("New Activity")
                    .foregroundStyle(.secondary)
                Spacer()
                Button { open(.folder) } label: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Folder")
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { if mode == nil { open(.activity) } }
    }

    private func open(_ newMode: Mode) {
        mode = newMode
        focused = true
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        draft = ""
        if mode == .folder {
            if !trimmed.isEmpty { onAddFolder(trimmed) }
            collapse()
            return
        }
        if !trimmed.isEmpty { onAdd(trimmed) }
        // Stay open — adding several in a row is the common case on first launch.
        focused = true
    }

    private func collapse() {
        draft = ""
        mode = nil
        focused = false
    }
}
