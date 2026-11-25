import SwiftUI
import AppKit

/// The validated categorical palette.
///
/// Eight slots, in a fixed order chosen so that *adjacent* slots stay separable under
/// colour-vision deficiency. Verified with the dataviz validator against macOS's real
/// window backgrounds (#ECECEC light, #1E1E1E dark):
///
///   light — worst adjacent CVD ΔE 9.1, normal-vision ΔE 19.6, all bands pass
///   dark  — worst adjacent CVD ΔE 8.4, normal-vision ΔE 19.3, all ≥ 3:1 contrast
///
/// Light mode warns that orange/aqua/yellow/magenta sit below 3:1 on the window
/// background. That is discharged by the "relief rule": the activity rows below the
/// chart are a full table view carrying name and exact hours for every slice.
///
/// There is no ninth hue. A generated one is indistinguishable from an existing slot
/// under CVD, so overflow activities take neutral grey and lean on their row.
///
/// Past the palette, a person can pick any colour they like in the colour window.
/// Such a custom colour still travels as one `Int` slot — `customBase` plus its 24-bit
/// sRGB value — so storage, friends and charts carry it without knowing it is special.
/// It is the same in light and dark mode, and it gets none of the palette's CVD checks.
enum Palette {
    static let lightHexes = [
        "#2a78d6", // 1 blue
        "#eb6834", // 2 orange
        "#1baf7a", // 3 aqua
        "#eda100", // 4 yellow
        "#e87ba4", // 5 magenta
        "#008300", // 6 green
        "#4a3aa7", // 7 violet
        "#e34948", // 8 red
    ]

    static let darkHexes = [
        "#3987e5", "#d95926", "#199e70", "#c98500",
        "#d55181", "#008300", "#9085e9", "#e66767",
    ]

    /// Slot 8+ — deliberately not a hue.
    static let overflowHex = "#898781"

    static var slotCount: Int { lightHexes.count }

    /// Slots from here on are custom colours: `customBase + 0xRRGGBB`.
    static let customBase = 0x100_0000

    static func isCustom(_ slot: Int) -> Bool {
        slot >= customBase && slot <= customBase + 0xFF_FFFF
    }

    static func customSlot(rgb: Int) -> Int { customBase + (rgb & 0xFF_FFFF) }

    /// The slot's colour as 0xRRGGBB, taking the light-mode value for palette slots.
    static func rgb(slot: Int) -> Int {
        if isCustom(slot) { return slot - customBase }
        let hexes = Palettes.shared.active.colors
        let hex = (slot >= 0 && slot < hexes.count) ? hexes[slot] : overflowHex
        return Int(hex.dropFirst(), radix: 16) ?? 0
    }

    /// The slot as friends should see it. Their app paints palette slots in *their*
    /// palette, so under any palette but the standard one a slot goes out as the
    /// custom colour it shows here.
    static func shared(slot: Int) -> Int {
        guard slot >= 0, slot < slotCount, Palettes.shared.active.id != ColorPalette.standard.id
        else { return slot }
        return customSlot(rgb: rgb(slot: slot))
    }

    /// `palette` overrides the active one. Friends' charts pass `.standard`: a friend's
    /// palette slots are the standard colours they see, not ours.
    static func color(slot: Int, palette override: ColorPalette? = nil) -> Color {
        if isCustom(slot) { return Color(nsColor: NSColor(rgb: slot - customBase)) }
        // Read here, in the caller's body, so SwiftUI redraws it when the palette changes.
        let palette = override ?? Palettes.shared.active
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hexes = isDark ? palette.darkColors ?? palette.colors : palette.colors
            let hex = (slot >= 0 && slot < hexes.count) ? hexes[slot] : overflowHex
            return NSColor(hex: hex)
        })
    }

    /// Lowest slot not already taken, else overflow grey.
    static func nextSlot(taken: [Int]) -> Int {
        for slot in 0..<slotCount where !taken.contains(slot) { return slot }
        return slotCount
    }
}

/// Chart chrome. Marks carry colour; text never does.
enum Ink {
    static let primary = Color.primary
    static let secondary = Color.secondary
    static let muted = Color(nsColor: NSColor(hex: "#898781"))
    /// A shade darker than the system window (#ECECEC / #1E1E1E).
    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(hex: isDark ? "#171717" : "#E2E2E2")
    })
}

extension Ink {
    /// A row lifted off the list while dragged: opaque, a step lighter than the card.
    static let raised = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(hex: isDark ? "#3A3A3C" : "#FFFFFF")
    })
}

/// Springs, after Apple's fluid-interface guidance: critically damped by default, so
/// nothing overshoots, and interruptible, so a gesture can redirect anything mid-flight.
enum Motion {
    /// State changes: rows sliding aside, folders opening, hover.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 1)
    /// A dragged row landing in its slot — the one place a little bounce is earned,
    /// because a hand just threw it there.
    static let settle = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// Wedges growing when time is added.
    static let chart = Animation.spring(response: 0.45, dampingFraction: 1)
    /// What Reduce Motion gets instead: a short cross-fade, no travel or bounce.
    static let reduced = Animation.easeInOut(duration: 0.2)
}

extension View {
    /// Liquid Glass on macOS 26, and the frosted material it replaced before that.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

extension NSColor {
    convenience init(rgb v: Int) {
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    convenience init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            srgbRed: CGFloat((v & 0xFF0000) >> 16) / 255,
            green: CGFloat((v & 0x00FF00) >> 8) / 255,
            blue: CGFloat(v & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
