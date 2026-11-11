import Foundation

/// The room, in points, a route map leaves around the route when it fits the
/// camera. The bottom is deeper so the attribution strip, drawn bottom-trailing,
/// never covers the route or its start dot.
public struct RouteFitPadding: Equatable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// 24 pt on three sides, 50 pt at the bottom for the attribution.
    public static let standard = RouteFitPadding(top: 24, left: 24, bottom: 50, right: 24)
}
