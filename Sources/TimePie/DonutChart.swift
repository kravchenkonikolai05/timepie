import SwiftUI
import AppKit
import Charts

struct Slice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let minutes: Int
    let colorSlot: Int
    /// The folder the task sits in, so the chart can show which slices belong together.
    var group: UUID? = nil
}

/// Part-to-whole at a glance. 100% is the time you logged, not the whole week.
///
/// Drawn with Swift Charts as rounded sectors with a hairline gap between them, the
/// way the system's own charts look. Hovering a slice (or its row) lifts it, dims the
/// rest, and puts its name and hours in the centre.
///
/// A folder's slices sit side by side, with a thin arc just outside them carrying the
/// folder's name in small letters. Hovering the arc or the folder's row lifts all of
/// its slices and puts the folder's total in the centre.
struct DonutChart: View {
    let slices: [Slice]
    var hoveredID: UUID?
    var compact: Bool = false
    /// A small grey line under the total, such as the average per day. Hidden while a
    /// slice is hovered, when the centre shows that slice instead.
    var caption: String? = nil
    /// Draws the folder arcs. Only the week's own chart has folders to show.
    var showsFolders: Bool = false
    /// Folder names, for the arcs and the centre while a folder is hovered.
    var groupNames: [UUID: String] = [:]
    var onHover: ((UUID?) -> Void)?

    private var total: Int { slices.reduce(0) { $0 + max(0, $1.minutes) } }
    private var shown: [Slice] { slices.filter { $0.minutes > 0 } }
    private var innerRatio: CGFloat { compact ? 0.52 : 0.64 }
    private var drawsFolders: Bool { showsFolders && !compact }

    /// Room left outside the ring for the folder arcs and their names.
    private var outerMargin: CGFloat { drawsFolders ? 7 : 0 }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let outerR = side / 2
            let ringR = outerR - outerMargin
            let innerR = ringR * innerRatio
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                if total == 0 {
                    // Empty skeleton: the ring holding its shape, waiting.
                    Circle()
                        .stroke(.quaternary, lineWidth: ringR - innerR)
                        .frame(width: ringR + innerR, height: ringR + innerR)
                } else {
                    chart
                        .frame(width: ringR * 2, height: ringR * 2)
                    if drawsFolders {
                        folderArcs(radius: ringR + FolderArc.gap)
                    }
                }

                if !compact {
                    centerFigure
                        .frame(width: max(0, innerR * 2 - 24))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Which slice the pointer is over is worked out from its angle and radius,
            // rather than trusting whichever shape happens to be on top.
            .onContinuousHover { phase in
                guard !compact, let notify = onHover else { return }
                switch phase {
                case .active(let point):
                    notify(hitID(at: point, centre: centre, innerR: innerR,
                                 ringR: ringR, outerR: outerR))
                case .ended:
                    notify(nil)
                @unknown default:
                    notify(nil)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func isLifted(_ slice: Slice) -> Bool {
        guard let hoveredID else { return false }
        return slice.id == hoveredID || slice.group == hoveredID
    }

    private var chart: some View {
        // Empty slices stay in the chart, at zero and invisible, so a slice that comes
        // or goes grows from or shrinks to nothing instead of changing the set.
        Chart(slices) { slice in
            let lifted = isLifted(slice)
            SectorMark(
                angle: .value("Minutes", max(0, slice.minutes)),
                innerRadius: .ratio(innerRatio),
                outerRadius: .ratio(lifted || compact ? 1 : 0.95),
                angularInset: compact ? 0.5 : 1.5
            )
            .cornerRadius(compact ? 1.5 : 5)
            .foregroundStyle(Palette.color(slot: slice.colorSlot))
            .opacity(slice.minutes <= 0 ? 0 : hoveredID == nil || lifted ? 1 : 0.4)
        }
        .chartLegend(.hidden)
        // Swift Charts traps when a sector animation is interrupted by a different set
        // of sectors (delete a row, then flip the week mid-animation). A new set of
        // slices gets a fresh chart instead; resizing the existing ones still animates.
        .id(slices.map(\.id))
        .animation(Motion.chart, value: slices)
        .animation(Motion.snappy, value: hoveredID)
    }

    // MARK: - Folder arcs

    /// One folder's run of slices, as fractions of the way round from 12 o'clock.
    private struct Span: Identifiable, Equatable {
        let id: UUID
        var start: Double
        var end: Double
        var middle: Double { (start + end) / 2 }
    }

    private var spans: [Span] {
        guard total > 0 else { return [] }
        var out: [Span] = []
        var cursor = 0.0
        var lastGroup: UUID?
        for slice in shown {
            let start = cursor / Double(total)
            cursor += Double(slice.minutes)
            let end = cursor / Double(total)
            if let group = slice.group, group == lastGroup, var last = out.popLast() {
                last.end = end
                out.append(last)
            } else if let group = slice.group {
                out.append(Span(id: group, start: start, end: end))
            }
            lastGroup = slice.group
        }
        return out
    }

    private func folderArcs(radius: CGFloat) -> some View {
        let circumference = 2 * .pi * radius
        // Pulled in at both ends so the round caps finish level with the slices' edges.
        let capPad = Double((FolderArc.width / 2 + 2) / circumference)
        return ZStack {
            ForEach(spans) { span in
                let lifted = hoveredID == span.id
                let ink = lifted ? Ink.secondary : Ink.muted
                let name = groupNames[span.id] ?? ""
                // On the lower half the name turns over, so it still reads left to right.
                let flipped = span.middle > 0.25 && span.middle < 0.75
                let label = CurvedLabel(text: name, radius: radius, upsideDown: flipped)
                // The arc breaks around the name, with a little air either side.
                let half = Double((label.width / 2 + FolderArc.labelGap) / circumference)
                let fits = !name.isEmpty && span.end - span.start > 2 * (half + capPad + 0.01)

                if fits {
                    arc(from: span.start + capPad, to: span.middle - half, radius: radius, ink: ink)
                    arc(from: span.middle + half, to: span.end - capPad, radius: radius, ink: ink)
                    label
                        .foregroundStyle(ink)
                        .rotationEffect(.radians(span.middle * 2 * .pi - (flipped ? .pi : 0)))
                } else {
                    arc(from: span.start + capPad, to: span.end - capPad, radius: radius, ink: ink)
                }
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .animation(Motion.chart, value: spans)
        .animation(Motion.snappy, value: hoveredID)
        .allowsHitTesting(false)
    }

    private func arc(from start: Double, to end: Double, radius: CGFloat, ink: Color) -> some View {
        Circle()
            .trim(from: start, to: max(start, end))
            .stroke(ink, style: StrokeStyle(lineWidth: FolderArc.width, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(-90))
    }

    // MARK: - Centre

    /// The one number the app leads with — or, while a slice or folder is hovered, its.
    private var centerFigure: some View {
        let focused = shown.first { $0.id == hoveredID }
        let folderMinutes = shown
            .filter { $0.group != nil && $0.group == hoveredID }
            .reduce(0) { $0 + $1.minutes }
        let label: String? = if let focused {
            "\(focused.name) · \(percent(focused.minutes))"
        } else if folderMinutes > 0, let id = hoveredID {
            "\(groupNames[id] ?? "Folder") · \(percent(folderMinutes))"
        } else {
            nil
        }
        let minutes = focused?.minutes ?? (folderMinutes > 0 ? folderMinutes : total)
        return VStack(spacing: 2) {
            Text(Duration.format(minutes: minutes))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(total == 0 ? .tertiary : .primary)
                .contentTransition(.numericText())
                // Hung just below the total rather than stacked with it, so the total
                // stays dead centre in the ring.
                // (An alignment guide is lost through the `if`, which laid it over the total.)
                .overlay(alignment: .top) {
                    if label == nil, let caption {
                        Text(caption)
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .fixedSize()
                            .offset(y: 40)
                    }
                }
            if let label {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .animation(Motion.snappy, value: hoveredID)
    }

    private func percent(_ minutes: Int) -> String {
        "\(Int((Double(minutes) / Double(max(total, 1)) * 100).rounded()))%"
    }

    // MARK: - Geometry

    /// The slice under the pointer, or the folder whose arc it's on.
    private func hitID(at point: CGPoint, centre: CGPoint,
                       innerR: CGFloat, ringR: CGFloat, outerR: CGFloat) -> UUID? {
        guard total > 0 else { return nil }

        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let radius = sqrt(dx * dx + dy * dy)

        // Screen y grows downward, so atan2 gives -π/2 at 12 o'clock; shifting by π/2
        // puts 0 there and makes the angle grow clockwise, as the chart draws.
        var angle = atan2(dy, dx) + Double.pi / 2
        if angle < 0 { angle += 2 * Double.pi }
        let fraction = angle / (2 * Double.pi)

        // The band the arcs run through answers for their folder.
        if drawsFolders && radius > ringR && radius <= outerR + 4 {
            return spans.first { fraction >= $0.start && fraction < $0.end }?.id
        }

        // Ignore the hole and anything outside the ring.
        guard radius >= innerR, radius <= ringR else { return nil }

        var cursor = 0.0
        for slice in shown {
            let share = Double(slice.minutes) / Double(total)
            if fraction >= cursor && fraction < cursor + share { return slice.id }
            cursor += share
        }
        return nil
    }
}

/// Sizes of the folder arcs.
private enum FolderArc {
    /// From the ring's outer edge (a lifted slice's) to the middle of the arc.
    static let gap: CGFloat = 1.5
    static let width: CGFloat = 1.5
    /// Space between the end of the arc and the name it breaks around.
    static let labelGap: CGFloat = 4
}

/// A short name set along a circle, centred at 12 o'clock (6 o'clock when upside down)
/// and rotated into place by the caller — rotating keeps it on the circle while its arc
/// animates. Each letter stands upright to the curve.
private struct CurvedLabel: View {
    let text: String
    let radius: CGFloat
    /// Set for a label on the lower half of the circle, so it reads left to right there.
    var upsideDown = false

    private static let font = NSFont.systemFont(ofSize: 9, weight: .medium)
    private static let tracking: CGFloat = 0.6

    private var advances: [CGFloat] {
        text.map { char in
            NSAttributedString(string: String(char), attributes: [.font: Self.font])
                .size().width + Self.tracking
        }
    }

    /// Length along the circle.
    var width: CGFloat { advances.reduce(0, +) - Self.tracking }

    var body: some View {
        let advances = advances
        let chars = Array(text)
        ZStack {
            ForEach(chars.indices, id: \.self) { i in
                let before = advances[..<i].reduce(0, +)
                let along = before + advances[i] / 2 - width / 2
                // Upside down it hangs from 6 o'clock, where a letter left as it is
                // already has its top towards the centre, and left to right there
                // runs anticlockwise.
                Text(String(chars[i]))
                    .font(Font(Self.font))
                    .fixedSize()
                    .offset(y: upsideDown ? radius : -radius)
                    .rotationEffect(.radians(Double(along / radius) * (upsideDown ? -1 : 1)))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

// Outside labels were removed deliberately: the activity rows below the chart are
// both the legend and the table view, so every name, value and percentage is already
// readable there — and the ring stays a clean object with nothing crowding it.
