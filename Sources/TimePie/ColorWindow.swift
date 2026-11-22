import AppKit
import SwiftUI

/// A colour as hue, saturation and brightness, each 0...1.
///
/// The window keeps this rather than RGB so that dragging brightness down to black,
/// or saturation down to grey, doesn't lose the hue the person was on.
struct HSV: Equatable {
    var h: Double
    var s: Double
    var v: Double

    init(h: Double, s: Double, v: Double) {
        self.h = h
        self.s = s
        self.v = v
    }

    init(rgb: Int) {
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
        var hue = 0.0
        if d > 0 {
            if hi == r {
                hue = (g - b) / d
            } else if hi == g {
                hue = (b - r) / d + 2
            } else {
                hue = (r - g) / d + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        self.init(h: hue, s: hi == 0 ? 0 : d / hi, v: hi)
    }

    /// 0xRRGGBB.
    var rgb: Int {
        let sector = floor(h * 6), f = h * 6 - sector
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let c: (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: c = (v, t, p)
        case 1: c = (q, v, p)
        case 2: c = (p, v, t)
        case 3: c = (p, q, v)
        case 4: c = (t, p, v)
        default: c = (v, p, q)
        }
        func byte(_ x: Double) -> Int { min(255, max(0, Int((x * 255).rounded()))) }
        return byte(c.0) << 16 | byte(c.1) << 8 | byte(c.2)
    }

    static func hex(_ rgb: Int) -> String { String(format: "#%06X", rgb & 0xFF_FFFF) }

    /// Reads "#2A78D6", "2a78d6" or the short "#29D". Nil for anything else.
    static func parseHex(_ text: String) -> Int? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit) else { return nil }
        return Int(s, radix: 16)
    }
}

/// Custom colours picked lately, newest first, so they're one click away next time.
enum CustomColors {
    private static let key = "recentCustomColors"
    /// One popover row's worth, the same width as the palette row.
    static let limit = 9

    static var recents: [Int] {
        (UserDefaults.standard.array(forKey: key) as? [Int] ?? []).filter(Palette.isCustom)
    }

    static func remember(_ slot: Int) {
        guard Palette.isCustom(slot) else { return }
        var list = recents.filter { $0 != slot }
        list.insert(slot, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }
}

/// One round, clickable colour. A ring marks the current one; a dot under it marks a
/// colour another activity already uses.
struct Swatch: View {
    let slot: Int
    let isCurrent: Bool
    let isTaken: Bool
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Palette.color(slot: slot))
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .strokeBorder(Ink.primary.opacity(isCurrent ? 0.85 : 0), lineWidth: 2)
                        .padding(-3)
                )
                .overlay(alignment: .bottom) {
                    if isTaken && !isCurrent {
                        Circle()
                            .fill(Ink.muted)
                            .frame(width: 3, height: 3)
                            .offset(y: 6)
                    }
                }
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help.isEmpty ? HSV.hex(Palette.rgb(slot: slot)) : help)
    }
}

/// The full colour window, opened from "More Colours…" in the row's colour popover.
///
/// Laid out like the pickers in drawing apps: a big grid of ready-made shades, a
/// spectrum to drag through, and RGB sliders, with a hex field, a screen eyedropper,
/// the palette and recent colours always in reach under them.
struct ColorWindow: View {
    let initialSlot: Int
    let taken: Set<Int>
    let onDone: (Int) -> Void
    let onCancel: () -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case grid = "Grid"
        case spectrum = "Spectrum"
        case sliders = "Sliders"
        var id: Self { self }
    }

    @AppStorage("colorWindowMode") private var mode: Mode = .grid
    @State private var hsv: HSV
    /// Set while the choice is one of the palette slots, so it stays a palette slot
    /// (and keeps its own dark-mode shade) rather than turning into a custom copy.
    @State private var paletteSlot: Int?
    @State private var hexDraft: String
    @FocusState private var hexFocused: Bool
    private let recents = CustomColors.recents

    init(initialSlot: Int, taken: Set<Int>,
         onDone: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.initialSlot = initialSlot
        self.taken = taken
        self.onDone = onDone
        self.onCancel = onCancel
        let rgb = Palette.rgb(slot: initialSlot)
        _hsv = State(initialValue: HSV(rgb: rgb))
        _paletteSlot = State(initialValue: Palette.isCustom(initialSlot) ? nil : initialSlot)
        _hexDraft = State(initialValue: HSV.hex(rgb))
    }

    private var chosenSlot: Int { paletteSlot ?? Palette.customSlot(rgb: hsv.rgb) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Colour")
                    .font(.headline)
                Spacer()
                preview
            }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch mode {
                case .grid:
                    ColorGrid(selected: paletteSlot == nil ? hsv.rgb : nil) { set(HSV(rgb: $0)) }
                case .spectrum:
                    SpectrumPad(hsv: hsv, onChange: set)
                case .sliders:
                    RGBSliders(rgb: hsv.rgb) { set(HSV(rgb: $0)) }
                }
            }
            .frame(height: 200)

            HStack(spacing: 8) {
                Text("Hex")
                    .foregroundStyle(Ink.secondary)
                TextField("#RRGGBB", text: $hexDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 96)
                    .focused($hexFocused)
                    .onSubmit(commitHex)
                    .onChange(of: hexFocused) { _, focused in
                        if !focused { commitHex() }
                    }
                Spacer()
                Button(action: sampleScreen) {
                    Image(systemName: "eyedropper")
                        .frame(width: 20)
                }
                .help("Pick up a colour from anywhere on the screen")
            }

            swatchSection("Palette", slots: Array(0...Palette.slotCount))
            if !recents.isEmpty {
                swatchSection("Recent", slots: recents)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    CustomColors.remember(chosenSlot)
                    onDone(chosenSlot)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340)
    }

    /// The colour the activity has now, beside the one it will get.
    private var preview: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Palette.color(slot: initialSlot))
            Rectangle().fill(Palette.color(slot: chosenSlot))
        }
        .frame(width: 56, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.primary.opacity(0.15)))
        .help("Before and after")
    }

    private func swatchSection(_ title: String, slots: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Ink.muted)
            HStack(spacing: 8) {
                ForEach(slots, id: \.self) { slot in
                    Swatch(slot: slot, isCurrent: slot == chosenSlot,
                           isTaken: taken.contains(slot) && slot != initialSlot,
                           help: slot == Palette.slotCount ? "Neutral grey" : "") {
                        pick(slot: slot)
                    }
                }
            }
        }
    }

    // MARK: - Changes

    private func set(_ new: HSV) {
        hsv = new
        paletteSlot = nil
        hexDraft = HSV.hex(new.rgb)
    }

    private func pick(slot: Int) {
        let rgb = Palette.rgb(slot: slot)
        hsv = HSV(rgb: rgb)
        paletteSlot = Palette.isCustom(slot) ? nil : slot
        hexDraft = HSV.hex(rgb)
    }

    private func commitHex() {
        guard let rgb = HSV.parseHex(hexDraft) else {
            hexDraft = HSV.hex(hsv.rgb) // Put back what's showing; a typo changes nothing.
            return
        }
        // Leaving the field untouched mustn't turn a palette slot into a custom copy.
        if rgb == hsv.rgb {
            hexDraft = HSV.hex(rgb)
        } else {
            set(HSV(rgb: rgb))
        }
    }

    private func sampleScreen() {
        NSColorSampler().show { picked in
            guard let c = picked?.usingColorSpace(.sRGB) else { return }
            func byte(_ x: CGFloat) -> Int { min(255, max(0, Int((x * 255).rounded()))) }
            let rgb = byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
            DispatchQueue.main.async { set(HSV(rgb: rgb)) }
        }
    }
}

// MARK: - Grid

/// Ready-made shades: a row of greys, then twelve hues running from pale to deep.
private struct ColorGrid: View {
    /// The current colour, outlined if it is one of the cells. Nil while on a palette slot.
    let selected: Int?
    let onPick: (Int) -> Void

    static let rows: [[Int]] = {
        let greys = (0..<12).map { i -> Int in
            let g = Int((Double(11 - i) / 11 * 255).rounded())
            return g << 16 | g << 8 | g
        }
        let shades: [(s: Double, v: Double)] = [
            (0.2, 1), (0.35, 1), (0.5, 1), (0.7, 1), (0.9, 1),
            (1, 0.85), (1, 0.7), (1, 0.55), (1, 0.4),
        ]
        let hues = shades.map { shade in
            (0..<12).map { HSV(h: Double($0) / 12, s: shade.s, v: shade.v).rgb }
        }
        return [greys] + hues
    }()

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(Self.rows[r].indices, id: \.self) { c in
                        cell(Self.rows[r][c])
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cell(_ rgb: Int) -> some View {
        Rectangle()
            .fill(Color(nsColor: NSColor(rgb: rgb)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if rgb == selected {
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onPick(rgb) }
            .help(HSV.hex(rgb))
    }
}

// MARK: - Spectrum

/// Saturation across, brightness down, for the hue chosen on the bar beneath.
private struct SpectrumPad: View {
    let hsv: HSV
    let onChange: (HSV) -> Void

    private static let hueStops = (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack {
                    Color(hue: hsv.h, saturation: 1, brightness: 1)
                    LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    knob(Color(nsColor: NSColor(rgb: hsv.rgb)))
                        .position(x: hsv.s * geo.size.width, y: (1 - hsv.v) * geo.size.height)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    var next = hsv
                    next.s = clamp(g.location.x / geo.size.width)
                    next.v = clamp(1 - g.location.y / geo.size.height)
                    onChange(next)
                })
            }

            GeometryReader { geo in
                LinearGradient(colors: Self.hueStops, startPoint: .leading, endPoint: .trailing)
                    .clipShape(Capsule())
                    .overlay {
                        knob(Color(hue: hsv.h, saturation: 1, brightness: 1))
                            .position(x: hsv.h * geo.size.width, y: geo.size.height / 2)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        var next = hsv
                        // Stops just short of 1, which is the same red as 0.
                        next.h = min(clamp(g.location.x / geo.size.width), 0.999)
                        onChange(next)
                    })
            }
            .frame(height: 16)
        }
    }

    private func knob(_ fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.35), radius: 1.5)
            .allowsHitTesting(false)
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}

// MARK: - Sliders

/// Red, green and blue, 0 to 255 each.
private struct RGBSliders: View {
    let rgb: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(spacing: 18) {
            channel("Red", shift: 16, tint: .red)
            channel("Green", shift: 8, tint: .green)
            channel("Blue", shift: 0, tint: .blue)
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    private func channel(_ name: String, shift: Int, tint: Color) -> some View {
        let value = (rgb >> shift) & 0xFF
        let binding = Binding<Double>(
            get: { Double(value) },
            set: { new in
                let byte = min(255, max(0, Int(new.rounded())))
                onChange((rgb & ~(0xFF << shift)) | byte << shift)
            }
        )
        return HStack(spacing: 10) {
            Text(name)
                .foregroundStyle(Ink.secondary)
                .frame(width: 44, alignment: .leading)
            Slider(value: binding, in: 0...255)
                .tint(tint)
            Text("\(value)")
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
    }
}
