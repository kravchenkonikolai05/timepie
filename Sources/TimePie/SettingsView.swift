import SwiftUI

/// Preferences, kept in UserDefaults. Each one is a key here and a row on the page.
enum Settings {
    /// The week's average per day, small and grey under the total in the donut.
    static let showDayAverage = "showDayAverage"
}

/// The settings page, in place of the week like stats, friends and the leaderboard.
/// Inset grouped cards of rows, as in System Settings; new settings are new rows.
struct SettingsView: View {
    /// The week the toolbar arrows are on; the palette preview shows it.
    let week: Date
    @AppStorage(Settings.showDayAverage) private var showDayAverage = false
    @Environment(Store.self) private var store
    @Environment(Friends.self) private var friends
    private var palettes = Palettes.shared
    /// The custom palette open in the editor sheet.
    @State private var editing: ColorPalette?
    /// The palette clicked last, opened under its row with a preview of the week.
    @State private var previewing: String?

    init(week: Date) {
        self.week = week
    }

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

    /// The viewed week's chart in the palette, and what can be done to the palette under it.
    private func preview(_ palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PalettePreview(slices: previewSlices())
            HStack(spacing: 8) {
                actions(palette)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
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

    /// The viewed week's time per task. Every task there has ever been is in the list,
    /// at zero in weeks it isn't part of, so the set never changes between weeks and
    /// the chart can animate from one week to the next.
    private func previewSlices() -> [Slice] {
        let start = WeekMath.weekStart(for: week)
        let end = WeekMath.weekEnd(for: start)
        let inWeek = Set(store.activities(forWeek: start).map(\.id))
        return store.activities.sorted { $0.sortIndex < $1.sortIndex }.map {
            Slice(id: $0.id, name: $0.name,
                  minutes: inWeek.contains($0.id)
                      ? max(0, store.minutes(activityID: $0.id, from: start, to: end)) : 0,
                  colorSlot: $0.colorSlot)
        }
    }
}

/// The week's donut in the palette, just to look at. A fixed size, so the page doesn't
/// jump when weeks have more or fewer tasks.
private struct PalettePreview: View {
    let slices: [Slice]

    var body: some View {
        DonutChart(slices: slices)
            .frame(width: 170, height: 170)
            .frame(maxWidth: .infinity)
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
