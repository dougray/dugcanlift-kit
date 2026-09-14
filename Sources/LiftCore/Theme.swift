import SwiftUI

/// Design tokens extracted from the Android build of LIFT.
/// Colours sampled directly from app screenshots — do not eyeball replacements.
public enum Theme {

    // MARK: Colour

    // These are the browser build's tokens, from dugcanlift-site/lift/style.css,
    // and they are the definition rather than an approximation of it. Four of
    // them had drifted: `surface` was a cool grey (0x36353B) where the web uses
    // a warm brown, and text/secondary/hairline were each a few points off.
    // The effect was not subtle in use -- every card on iPhone read blue-grey
    // against the web and Android's warm brown, which is what made the native
    // apps look worse than the PWA rather than merely different.
    //
    // The Kotlin side (dugcanlift-kit-android's DclPalette) already carried the
    // correct values and claimed in its own comment to match this file. It did
    // not. It does now.

    /// Warm near-black page background.
    public static let background = Color(hex: 0x1C1B19)
    /// Warm brown card surface. NOT a cool grey -- see the note above.
    public static let surface = Color(hex: 0x242220)
    /// Rust/burnt orange. Headings, active tab, filled chips, progress, destructive.
    public static let accent = Color(hex: 0xC1442C)
    /// Dimmed accent for pressed and disabled states.
    public static let accentMuted = Color(hex: 0x883223)
    /// Sage green. The web's `--accent-2`, used where a second accent is needed.
    public static let accentSecondary = Color(hex: 0x7C8B7A)
    /// Foreground on a filled accent surface. The web's button colour.
    public static let onAccent = Color(hex: 0xF7F1E8)

    public static let textPrimary = Color(hex: 0xEDE7DD)
    public static let textSecondary = Color(hex: 0xA39C8E)
    public static let hairline = Color(hex: 0x3A3733)

    // MARK: Metrics

    /// 12, matching the web's `.card` radius. Was 14.
    public static let cardRadius: CGFloat = 12
    public static let chipRadius: CGFloat = 9
    /// A pill. The web's buttons are `border-radius: 999px`.
    public static let pillRadius: CGFloat = 999
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

/// A tab in a top tab row, styled as the browser build styles one: muted text
/// that turns accent, with a 2px accent rule beneath it.
///
/// Named `LiftTabButton`, not `LiftTab`: lift-ios already has a `LiftTab` enum
/// naming its own tabs, and two visible types with one name is an ambiguity
/// waiting for whoever imports both.
///
/// Not a filled block. The native builds had been drawing the selected tab as a
/// solid accent rectangle, which reads as a button rather than a tab and is the
/// most visible difference between the native apps and the browser.
public struct LiftTabButton: View {
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
            VStack(spacing: 0) {
                Text(label)
                    // 14/600 with 1.2pt of tracking, from `nav button` in the
                    // web build's stylesheet.
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(isSelected ? Theme.accent : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The row those tabs sit in: a hairline beneath the whole thing, which each
/// selected tab's own rule overlaps.
public struct LiftTabBar<Content: View>: View {
    @ViewBuilder let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) { content }
            .background(alignment: .bottom) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
    }
}

/// A filled accent pill — the browser build's default `button`.
///
/// The native apps had been rendering primary actions as bare accent-coloured
/// text ("Set my goal"), which reads as a link and is easy to miss next to the
/// web's filled pill.
public struct LiftButton: View {
    let title: String
    let isGhost: Bool
    let action: () -> Void

    public init(_ title: String, isGhost: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isGhost = isGhost
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isGhost ? Theme.textPrimary : Theme.onAccent)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(isGhost ? Color.clear : Theme.accent)
                        .overlay { Capsule().stroke(isGhost ? Theme.hairline : .clear, lineWidth: 1) }
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
