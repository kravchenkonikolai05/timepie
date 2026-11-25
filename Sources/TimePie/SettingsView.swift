import SwiftUI

/// Preferences, kept in UserDefaults. Each one is a key here and a row on the page.
enum Settings {
    /// The week's average per day, small and grey under the total in the donut.
    static let showDayAverage = "showDayAverage"
}

/// The settings page, in place of the week like stats, friends and the leaderboard.
/// Inset grouped cards of rows, as in System Settings; new settings are new rows.
struct SettingsView: View {
    @AppStorage(Settings.showDayAverage) private var showDayAverage = false
    @Environment(Store.self) private var store
    @Environment(Friends.self) private var friends
    private var palettes = Palettes.shared
    /// The custom palette open in the editor sheet.
    @State private var editing: ColorPalette?
    /// The palette clicked last, opened under its row with a preview of this week.
    @State private var previewing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Chart")
            card {
                HStack {
                    Text("Show average per day")
                    Spacer()
                    Toggle("Show average per day", isOn: $showDayAverage)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(12)
            }

            heading("Colour Palette")
                .padding(.top, 14)
            card {
                ForEach(Array(palettes.all.enumerated()), id: \.element.id) { index, palette in
                    if index > 0 { Divider().padding(.leading, 12) }
                    paletteRow(palette)
                }
                Divider().padding(.leading, 12)
                Button {
                    editing = palettes.makeCopy(of: palettes.active)
                } label: {
                    Label("New Palette", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(12)
                .help("A new palette that starts as a copy of the one in use")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $editing) { palette in
            PaletteEditor(palette: palette)
        }
        // Friends see the colours you see, so a new palette goes out to the group.
        .onChange(of: palettes.active) { friends.storeChanged(store, after: 0, force: true) }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.leading, 12)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quinary))
    }

    private func paletteRow(_ palette: ColorPalette) -> some View {
        let isActive = palette.id == palettes.active.id
        let isOpen = previewing == palette.id
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .font(.title3)
                Text(palette.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                PaletteStrip(palette: palette)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture {
                palettes.activeID = palette.id
                withAnimation(Motion.snappy) { previewing = isOpen ? nil : palette.id }
            }

            if isOpen {
                preview(palette)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
        .contextMenu { actions(palette) }
    }

    /// This week's chart in the palette, drawn like a friend's week, and what can be
    /// done to the palette under it.
    private func preview(_ palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PalettePreview(slices: previewSlices())
            HStack(spacing: 8) {
                actions(palette)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.leading, 40)
        }
        .padding(.trailing, 12)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func actions(_ palette: ColorPalette) -> some View {
        if !palettes.isBuiltIn(palette.id) {
            Button("Edit…") { editing = palette }
        }
        Button("Duplicate") {
            editing = palettes.makeCopy(of: palette)
            previewing = editing?.id
        }
        if palettes.canDelete(palette.id) {
            Button("Delete", role: .destructive) {
                withAnimation(Motion.snappy) {
                    palettes.delete(id: palette.id)
                    previewing = nil
                }
            }
        }
    }

    /// Every task of this week with its time, the ones with none included, so the list
    /// shows each colour the palette gives them.
    private func previewSlices() -> [Slice] {
        let start = WeekMath.weekStart(for: Date())
        let end = WeekMath.weekEnd(for: start)
        return store.activities(forWeek: start).map {
            Slice(id: $0.id, name: $0.name,
                  minutes: max(0, store.minutes(activityID: $0.id, from: start, to: end)),
                  colorSlot: $0.colorSlot)
        }
    }
}

/// This week's donut and what it's made of, biggest first: the same card a friend's
/// week opens into on the friends page.
private struct PalettePreview: View {
    let slices: [Slice]

    @State private var hoveredID: UUID?

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            DonutChart(slices: slices, hoveredID: hoveredID, onHover: { hoveredID = $0 })
                .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(slices.sorted { $0.minutes > $1.minutes }) { slice in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Palette.color(slot: slice.colorSlot))
                            .frame(width: 9, height: 9)
                        Text(slice.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Duration.format(minutes: slice.minutes))
                            .monospacedDigit()
                            .foregroundStyle(slice.minutes == 0 ? Ink.muted : Ink.secondary)
                    }
                    .font(.callout)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(hoveredID == slice.id ? Color.primary.opacity(0.06) : .clear)
                    )
                    .onHover { hoveredID = $0 ? slice.id : nil }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, 40)
    }
}

/// A palette's eight colours as a row of dots, in the current appearance.
private struct PaletteStrip: View {
    var palette: ColorPalette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hexes = scheme == .dark ? palette.darkColors ?? palette.colors : palette.colors
        HStack(spacing: 4) {
            ForEach(Array(hexes.enumerated()), id: \.offset) { _, hex in
                Circle()
                    .fill(Color(nsColor: NSColor(hex: hex)))
                    .frame(width: 14, height: 14)
            }
        }
    }
}

/// Name and eight colour wells for a custom palette. Changes save as they are made, so
/// the chart behind the sheet shows them at once.
private struct PaletteEditor: View {
    @State var palette: ColorPalette
    @Environment(\.dismiss) private var dismiss
    private var palettes = Palettes.shared

    init(palette: ColorPalette) {
        _palette = State(initialValue: palette)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Name", text: $palette.name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                      spacing: 12) {
                ForEach(0..<palette.colors.count, id: \.self) { i in
                    VStack(spacing: 4) {
                        ColorPicker("", selection: binding(i), supportsOpacity: false)
                            .labelsHidden()
                        Text("\(i + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button("Delete Palette", role: .destructive) {
                    palettes.delete(id: palette.id)
                    dismiss()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onChange(of: palette) { palettes.update(palette) }
    }

    private func binding(_ i: Int) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: palette.colors[i])) },
            set: { palette.colors[i] = NSColor($0).hexString }
        )
    }
}
