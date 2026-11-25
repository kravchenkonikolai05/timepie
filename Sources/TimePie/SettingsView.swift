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
        let isCustom = !palettes.isBuiltIn(palette.id)
        return HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .font(.title3)
            Text(palette.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            PaletteStrip(palette: palette)
            if isCustom {
                Button { editing = palette } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit this palette")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { palettes.activeID = palette.id }
        .contextMenu {
            Button("Use") { palettes.activeID = palette.id }
            Button("Duplicate") { editing = palettes.makeCopy(of: palette) }
            if isCustom {
                Button("Edit…") { editing = palette }
                Divider()
                Button("Delete", role: .destructive) { palettes.delete(id: palette.id) }
            }
        }
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
