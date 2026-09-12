import SwiftUI

/// Design tokens extracted from the Android build of LIFT.
/// Colours sampled directly from app screenshots — do not eyeball replacements.
public enum Theme {

    // MARK: Colour

    /// Warm near-black page background.
    public static let background = Color(hex: 0x1C1B19)
    /// Slightly cool grey used for every card surface.
    public static let surface = Color(hex: 0x36353B)
    /// Rust/burnt orange. Headings, active tab, filled chips, progress, destructive.
    public static let accent = Color(hex: 0xC1442C)
    /// Dimmed accent for pressed and disabled states.
    public static let accentMuted = Color(hex: 0x883223)

    public static let textPrimary = Color(hex: 0xEFEDE9)
    public static let textSecondary = Color(hex: 0x9B9995)
    public static let hairline = Color(hex: 0x4A484E)

    // MARK: Metrics

    public static let cardRadius: CGFloat = 14
    public static let chipRadius: CGFloat = 9
    public static let cardPadding: CGFloat = 16
    public static let cardSpacing: CGFloat = 12

    // MARK: Type

    /// Orange card heading — "Training", "Fuel so far today".
    public static let cardTitle = Font.system(size: 17, weight: .bold)
    /// Large figure — "635 kcal over".
    public static let figure = Font.system(size: 26, weight: .bold)
    public static let body = Font.system(size: 16)
    public static let detail = Font.system(size: 14)
    public static let sectionLabel = Font.system(size: 15, weight: .bold)
}

extension Color {
    public init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Components

/// The card that carries almost every surface in the app.
public struct LiftCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    public init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.accent)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// Outlined when unselected, filled rust when selected — as in the Focus and
/// Activity rows.
public struct LiftChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    public init(label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: Theme.chipRadius)
                        .fill(isSelected ? Theme.accent : .clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.chipRadius)
                                .stroke(isSelected ? .clear : Theme.hairline, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
    }
}

/// Label left, value right, with a full-width progress rule beneath —
/// the macro rows on the Home tab.
public struct MacroProgressRow: View {
    let label: String
    let current: Double
    let goal: Double
    let unit: String

    public init(label: String, current: Double, goal: Double, unit: String) {
        self.label = label
        self.current = current
        self.goal = goal
        self.unit = unit
    }

    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(current / goal, 1)
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(current)) / \(Int(goal)) \(unit)")
                    .font(Theme.body)
                    .foregroundStyle(Theme.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline.opacity(0.5))
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)
        }
    }
}

/// Plain label/value row — the "Fuel so far today" list.
public struct StatRow: View {
    let label: String
    let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack {
            Text(label).font(Theme.body).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value).font(Theme.body).foregroundStyle(Theme.textPrimary)
        }
    }
}

extension View {
    /// Applies the page background and default text colour.
    ///
    /// `.scrollBounceBehavior(.always)` is deliberate: without it a ScrollView
    /// whose content fits the screen is completely inert, which is
    /// indistinguishable from broken scrolling.
    public func liftScreen() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollBounceBehavior(.always)
            .tint(Theme.accent)
            .foregroundStyle(Theme.textPrimary)
    }
}
