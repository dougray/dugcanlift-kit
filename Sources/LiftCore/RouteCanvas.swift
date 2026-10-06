import SwiftUI

/// A route drawn with no map behind it — LIFT Android's `RoutePolylineCanvas`
/// and Coach web's canvas, for iPhone. The line in the accent colour, a
/// half-strength dot where it started and a full one where it ends — which,
/// during a recording, is where you are. Under two points it says
/// "Waiting for GPS…".
///
/// No tiles means no server learns where the route is. The distance and time
/// beside it on every card carry the facts in words, so the drawing reads as a
/// single element, "Route".
public struct RouteCanvas: View {

    public static let waitingText = "Waiting for GPS…"
    public static let accessibilityName = "Route"

    let points: [OutdoorShareCoordinate]
    /// Width over height. Square on recording and review; nil lets a card that
    /// already sets a height keep it.
    let aspectRatio: CGFloat?

    public init(points: [OutdoorShareCoordinate], aspectRatio: CGFloat? = nil) {
        self.points = points
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        // Only when given: `.aspectRatio(nil, …)` falls back to the content's
        // ideal ratio, which a plain fill does not have.
        Group {
            if let aspectRatio {
                panel.aspectRatio(aspectRatio, contentMode: .fit)
            } else {
                panel
            }
        }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityName)
    }

    private var panel: some View {
        ZStack {
            Theme.background
            if points.count < 2 {
                Text(Self.waitingText)
                    .font(Theme.detail)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Canvas { context, size in
                    // Return early when the canvas has no usable dimensions; the first layout pass can be zero-sized.
                    guard size.width > 0, size.height > 0 else { return }
                    let projected = RouteProjection.project(points, width: Double(size.width),
                                                            height: Double(size.height))
                    var path = Path()
                    path.addLines(projected)
                    context.stroke(path, with: .color(Theme.accent),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    if let start = projected.first {
                        context.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)),
                                     with: .color(Theme.accent.opacity(0.5)))
                    }
                    if let end = projected.last {
                        context.fill(Path(ellipseIn: CGRect(x: end.x - 6, y: end.y - 6, width: 12, height: 12)),
                                     with: .color(Theme.accent))
                    }
                }
            }
        }
    }
}
