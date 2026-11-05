import SwiftUI
import Charts

struct Slice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let minutes: Int
    let colorSlot: Int
}

/// Part-to-whole at a glance. 100% is the time you logged, not the whole week.
///
/// Drawn with Swift Charts as rounded sectors with a hairline gap between them, the
/// way the system's own charts look. Hovering a slice (or its row) lifts it, dims the
/// rest, and puts its name and hours in the centre.
struct DonutChart: View {
    let slices: [Slice]
    var hoveredID: UUID?
    var compact: Bool = false
    /// A small grey line under the total, such as the average per day. Hidden while a
    /// slice is hovered, when the centre shows that slice instead.
    var caption: String? = nil
    var onHover: ((UUID?) -> Void)?

    private var total: Int { slices.reduce(0) { $0 + max(0, $1.minutes) } }
    private var shown: [Slice] { slices.filter { $0.minutes > 0 } }
    private var innerRatio: CGFloat { compact ? 0.52 : 0.64 }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let outerR = side / 2
            let innerR = outerR * innerRatio
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                if total == 0 {
                    // Empty skeleton: the ring holding its shape, waiting.
                    Circle()
                        .stroke(.quaternary, lineWidth: outerR - innerR)
                        .frame(width: outerR + innerR, height: outerR + innerR)
                } else {
                    chart
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
                    notify(sliceID(at: point, centre: centre, innerR: innerR, outerR: outerR))
                case .ended:
                    notify(nil)
                @unknown default:
                    notify(nil)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var chart: some View {
        // Empty slices stay in the chart, at zero and invisible, so a slice that comes
        // or goes grows from or shrinks to nothing instead of changing the set.
        Chart(slices) { slice in
            let lifted = hoveredID == slice.id
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

    /// The one number the app leads with — or, while a slice is hovered, that slice's.
    private var centerFigure: some View {
        let focused = shown.first { $0.id == hoveredID }
        let minutes = focused?.minutes ?? total
        return VStack(spacing: 2) {
            Text(Duration.format(minutes: minutes))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(total == 0 ? .tertiary : .primary)
                .contentTransition(.numericText())
                // Hung just below the total rather than stacked with it, so the total
                // stays dead centre in the ring.
                .overlay(alignment: .bottom) {
                    if focused == nil, let caption {
                        Text(caption)
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .fixedSize()
                            .alignmentGuide(.bottom) { $0[.top] - 2 }
                    }
                }
            if let focused {
                Text("\(focused.name) · \(percent(focused))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .animation(Motion.snappy, value: hoveredID)
    }

    private func percent(_ slice: Slice) -> String {
        "\(Int((Double(slice.minutes) / Double(max(total, 1)) * 100).rounded()))%"
    }

    // MARK: - Geometry

    private func sliceID(at point: CGPoint, centre: CGPoint,
                         innerR: CGFloat, outerR: CGFloat) -> UUID? {
        guard total > 0 else { return nil }

        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let radius = sqrt(dx * dx + dy * dy)
        // Ignore the hole and anything outside the ring.
        guard radius >= innerR, radius <= outerR else { return nil }

        // Screen y grows downward, so atan2 gives -π/2 at 12 o'clock; shifting by π/2
        // puts 0 there and makes the angle grow clockwise, as the chart draws.
        var angle = atan2(dy, dx) + Double.pi / 2
        if angle < 0 { angle += 2 * Double.pi }

        var cursor = 0.0
        for slice in shown {
            let sweep = (Double(slice.minutes) / Double(total)) * 2 * Double.pi
            if angle >= cursor && angle < cursor + sweep { return slice.id }
            cursor += sweep
        }
        return nil
    }
}

// Outside labels were removed deliberately: the activity rows below the chart are
// both the legend and the table view, so every name, value and percentage is already
// readable there — and the ring stays a clean object with nothing crowding it.
