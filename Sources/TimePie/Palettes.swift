import AppKit
import SwiftUI

/// Eight colours for the eight palette slots, under a name.
///
/// Activities store a slot, not a colour, so choosing another palette repaints every
/// task on slots 0–7 at once. Custom colours from the colour window stay as they are.
struct ColorPalette: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Eight "#rrggbb" values, one per slot.
    var colors: [String]
    /// Dark-mode shades. Only the standard palette has them; others look the same in both.
    var darkColors: [String]? = nil

    static let standard = ColorPalette(
        id: "standard", name: "Standard",
        colors: Palette.lightHexes, darkColors: Palette.darkHexes)

    /// The standard palette is the only one checked for colour-vision deficiency.
    static let builtIn: [ColorPalette] = [
        standard,
        ColorPalette(id: "winter-forest", name: "Winter Forest", colors: [
            "#70cd4a", "#dbe54c", "#ebf1e5", "#344bb5", "#4da6ff", "#cbe9fd", "#9085e9", "#4d4dff",
        ]),
        ColorPalette(id: "sunset", name: "Sunset", colors: [
            "#ff595e", "#ff924c", "#ffca3a", "#f15bb5", "#9b5de5", "#c9184a", "#ffb4a2", "#6a4c93",
        ]),
        ColorPalette(id: "ocean", name: "Ocean", colors: [
            "#0096c7", "#48cae4", "#2ec4b6", "#90e0ef", "#3a86ff", "#06d6a0", "#caf0f8", "#4361ee",
        ]),
        ColorPalette(id: "autumn", name: "Autumn", colors: [
            "#bc4b51", "#f4a259", "#8cb369", "#f4e285", "#5b8e7d", "#d1495b", "#edae49", "#a5668b",
        ]),
        ColorPalette(id: "pastel", name: "Pastel", colors: [
            "#ffadad", "#ffd6a5", "#fdffb6", "#caffbf", "#9bf6ff", "#a0c4ff", "#bdb2ff", "#ffc6ff",
        ]),
    ]
}

/// The palette in use and the ones a person made, kept in UserDefaults.
@Observable
final class Palettes {
    static let shared = Palettes()

    private static let activeKey = "palette"
    private static let customKey = "customPalettes"

    var activeID: String {
        didSet { UserDefaults.standard.set(activeID, forKey: Palettes.activeKey) }
    }

    var custom: [ColorPalette] {
        didSet {
            if let data = try? JSONEncoder().encode(custom) {
                UserDefaults.standard.set(data, forKey: Palettes.customKey)
            }
        }
    }

    var all: [ColorPalette] { ColorPalette.builtIn + custom }

    /// Falls back to the standard palette if the chosen one was deleted.
    var active: ColorPalette {
        all.first { $0.id == activeID } ?? .standard
    }

    private init() {
        let defaults = UserDefaults.standard
        activeID = defaults.string(forKey: Palettes.activeKey) ?? ColorPalette.standard.id
        custom = defaults.data(forKey: Palettes.customKey)
            .flatMap { try? JSONDecoder().decode([ColorPalette].self, from: $0) } ?? []
    }

    func isBuiltIn(_ id: String) -> Bool { ColorPalette.builtIn.contains { $0.id == id } }

    /// A new palette, copied from `source`, added to the list and made active.
    @discardableResult
    func makeCopy(of source: ColorPalette) -> ColorPalette {
        var names = Set(all.map(\.name))
        var name = source.id == ColorPalette.standard.id ? "My Palette" : "\(source.name) Copy"
        var n = 2
        let base = name
        while names.contains(name) { name = "\(base) \(n)"; n += 1 }
        names.insert(name)
        let palette = ColorPalette(id: UUID().uuidString, name: name, colors: source.colors)
        custom.append(palette)
        activeID = palette.id
        return palette
    }

    func update(_ palette: ColorPalette) {
        guard let i = custom.firstIndex(where: { $0.id == palette.id }) else { return }
        custom[i] = palette
    }

    func delete(id: String) {
        custom.removeAll { $0.id == id }
        if activeID == id { activeID = ColorPalette.standard.id }
    }
}

extension NSColor {
    /// "#rrggbb" in sRGB.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
