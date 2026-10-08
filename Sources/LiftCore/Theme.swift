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

    // Light values were designed on 2026-09-16 to the same warm brown-and-rust
    // brand rather than resampled from anything, and every text pairing was
    // checked against WCAG AA (4.5:1). The rust and sage both darken in light:
    // at their dark-mode values they fall to 3.4:1 and 4.4:1 on a pale ground.
    // Change a value here and the web's `[data-theme]` blocks and Android's
    // DclPalette must change with it -- this file is the canonical source.

    /// Warm near-black page background. Parchment in light.
    public static let background = Color(light: 0xF4EFE7, dark: 0x1C1B19)
    /// Warm brown card surface. NOT a cool grey -- see the note above. Near-white in light.
    public static let surface = Color(light: 0xFFFCF7, dark: 0x242220)
    /// Rust/burnt orange as a FILL: filled chips and buttons, progress, the
    /// active tab's rule. Not for text in dark: 0xC1442C is 3.39:1 on
    /// `background` and 3.12:1 on `surface`, below AA. Use `accentText`.
    public static let accent = Color(light: 0xB23C25, dark: 0xC1442C)
    /// Rust as TEXT: card titles, macro values, the active tab's label.
    /// Light is the same rust as `accent` (5.14:1 / 5.75:1). Dark is lifted to
    /// 0xE0674D: 5.09:1 on `background`, 4.69:1 on `surface`. Added 2026-10-08.
    public static let accentText = Color(light: 0xB23C25, dark: 0xE0674D,
                                         lightHighContrast: HighContrast.accentText.light,
                                         darkHighContrast: HighContrast.accentText.dark)
    /// Dimmed accent for pressed and disabled states. Put `textPrimary` on it,
    /// not `onAccent` (which is 1.77:1 on the light value).
    public static let accentMuted = Color(light: 0xE7B3A6, dark: 0x883223)
    /// Sage green as a FILL or LINE: dots, rules, strokes, the route's start
    /// marker. The web's `--accent-2`. Not for text in dark: 0x7C8B7A is
    /// 4.40:1 on `surface`, below AA. Use `accentSecondaryText`.
    public static let accentSecondary = Color(light: 0x56664F, dark: 0x7C8B7A)
    /// Sage as TEXT. Light is the same sage as `accentSecondary` (5.38:1 on
    /// `background`, 6.02:1 on `surface`). Dark is lifted, same hue, to
    /// 0x879585: 5.46:1 on `background`, 5.03:1 on `surface` (4.54:1 even on
    /// 0x2C2A27). Increase Contrast: 0x465341 (7.13:1 / 7.97:1) and 0xA6B0A4
    /// (7.68:1 / 7.07:1). Added 2026-10-08 in 1.14.0.
    public static let accentSecondaryText = Color(light: 0x56664F, dark: 0x879585,
                                                  lightHighContrast: HighContrast.accentSecondaryText.light,
                                                  darkHighContrast: HighContrast.accentSecondaryText.dark)
    /// Foreground on a filled accent surface. The web's button colour.
    public static let onAccent = Color(light: 0xFFFAF3, dark: 0xF7F1E8)

    public static let textPrimary = Color(light: 0x26221E, dark: 0xEDE7DD)
    public static let textSecondary = Color(light: 0x665E52, dark: 0xA39C8E,
                                            lightHighContrast: HighContrast.textSecondary.light,
                                            darkHighContrast: HighContrast.textSecondary.dark)
    /// 1.3-1.45:1 against the grounds: decoration, not a boundary. Under
    /// Increase Contrast it reaches 3:1 (WCAG 1.4.11), because it is the only
    /// edge of an unselected chip and a ghost button.
    public static let hairline = Color(light: 0xDCD3C5, dark: 0x3A3733,
                                       lightHighContrast: HighContrast.hairline.light,
                                       darkHighContrast: HighContrast.hairline.dark)

    /// The line round a card. Clear in dark, where a card already separates
    /// from the page by being lighter; a hairline in light, where parchment
    /// and near-white are too close in brightness to do that on their own.
    /// Under Increase Contrast both appearances get the 3:1 hairline.
    public static let cardBorder = Color(light: 0xDCD3C5, dark: nil,
                                         lightHighContrast: HighContrast.hairline.light,
                                         darkHighContrast: HighContrast.hairline.dark)

    /// Values used when Increase Contrast is on. Tokens not listed here do
    /// not change. Internal so ThemeTests can check them: macOS cannot build a
    /// high-contrast `NSAppearance` to resolve the colours through.
    enum HighContrast {
        static let accentText: (light: UInt32, dark: UInt32) = (0x962F1B, 0xEE8A70)
        static let accentSecondaryText: (light: UInt32, dark: UInt32) = (0x465341, 0xA6B0A4)
        static let textSecondary: (light: UInt32, dark: UInt32) = (0x4E473D, 0xC9C2B5)
        /// Also `cardBorder`'s, in both appearances.
        static let hairline: (light: UInt32, dark: UInt32) = (0x857B6C, 0x777065)
    }

    /// The tint `liftScreen()` applies: rust as TEXT, so tinted text buttons,
    /// links and controls read at AA in dark. Was `accent` (3.39:1) before 1.13.0.
    static let screenTint: Color = accentText

    // MARK: Metrics

    /// 12, matching the web's `.card` radius. Was 14.
    public static let cardRadius: CGFloat = 12
    public static let chipRadius: CGFloat = 9
    /// A pill. The web's buttons are `border-radius: 999px`.
    public static let pillRadius: CGFloat = 999
    public static let cardPadding: CGFloat = 16
    public static let cardSpacing: CGFloat = 12

    // MARK: Type

    // Every token is a Dynamic Type text style, so it follows the person's
    // reading size (2026-10-08). They were fixed `Font.system(size:)` values,
    // which never scale. At the default size most land on the old point size:
    // headline 17, callout 16, subheadline 15. Two had no exact style and
    // moved to the nearest one: `detail` 14 -> 15 and `figure` 26 -> 28.

    /// Orange card heading — "Training", "Fuel so far today". Headline (17), bold.
    public static let cardTitle = Font.system(.headline, weight: .bold)
    /// Large figure — "635 kcal over". Title (28), bold.
    public static let figure = Font.system(.title, weight: .bold)
    /// Callout (16).
    public static let body = Font.system(.callout)
    /// Subheadline (15).
    public static let detail = Font.system(.subheadline)
    /// Subheadline (15), bold.
    public static let sectionLabel = Font.system(.subheadline, weight: .bold)
    /// The label on a chip or a button. Subheadline (15).
    public static let control = Font.system(.subheadline, weight: .semibold)
}

extension Color {
    /// A colour that follows the interface style: light on a light screen,
    /// dark on a dark one, including when `AppAppearance` forces one of them.
    ///
    /// Built on the platform colour's dynamic provider rather than
    /// `@Environment(\.colorScheme)`, so every existing `Theme.surface` call
    /// site adapts without being rewritten. `dark: nil` means clear in dark.
    ///
    /// The high-contrast values are used when Increase Contrast is on; nil
    /// means "same as the normal value".
    public init(light: UInt32, dark: UInt32?,
                lightHighContrast: UInt32? = nil, darkHighContrast: UInt32? = nil) {
        func pick(isDark: Bool, isHigh: Bool) -> UInt32? {
            Color.resolve(light: light, dark: dark, lightHighContrast: lightHighContrast,
                          darkHighContrast: darkHighContrast, isDark: isDark, isHighContrast: isHigh)
        }
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            pick(isDark: traits.userInterfaceStyle == .dark,
                 isHigh: traits.accessibilityContrast == .high)
                .map(UIColor.init(hex:)) ?? .clear
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let isHigh = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            return pick(isDark: isDark, isHigh: isHigh).map(NSColor.init(hex:)) ?? .clear
        })
        #else
        self.init(hex: light)
        #endif
    }

    /// Which value a dynamic colour shows. nil means clear.
    static func resolve(light: UInt32, dark: UInt32?, lightHighContrast: UInt32?,
                        darkHighContrast: UInt32?, isDark: Bool, isHighContrast: Bool) -> UInt32? {
        if isDark { return (isHighContrast ? darkHighContrast : nil) ?? dark }
        return (isHighContrast ? lightHighContrast : nil) ?? light
    }

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

#if canImport(UIKit)
import UIKit
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#elseif canImport(AppKit)
import AppKit
extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

// MARK: - Appearance

/// Light, dark, or whatever the phone is set to.
///
/// **System is the default**, decided 2026-09-16: an app should follow the
/// phone unless told otherwise, and someone who wants dark on a light-mode
/// phone picks it once. Stored under `appearanceKey` in `@AppStorage`.
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public static let appearanceKey = "appearance"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// For `.preferredColorScheme`. nil hands control back to the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Applies the person's appearance choice.
///
/// Needed on the root view **and on every sheet**: a sheet is its own
/// presentation, and the native builds had been pinning each one to
/// `.preferredColorScheme(.dark)` for exactly that reason.
private struct AppAppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.appearanceKey) private var raw = AppAppearance.system.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme((AppAppearance(rawValue: raw) ?? .system).colorScheme)
    }
}

extension View {
    /// Follows the person's System / Light / Dark choice.
    public func liftAppearance() -> some View {
        modifier(AppAppearanceModifier())
    }
}

/// The System / Light / Dark control, so both apps offer the same one.
public struct AppearancePicker: View {
    @AppStorage(AppAppearance.appearanceKey) private var raw = AppAppearance.system.rawValue

    public init() {}

    public var body: some View {
        Picker("Appearance", selection: $raw) {
            ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
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
                    .foregroundStyle(Theme.accentText)
                    // Cards are the only structure on most screens; this puts
                    // them in VoiceOver's Headings rotor.
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .liftCardBackground()
    }
}

/// Outlined when unselected, filled rust when selected — as in the Focus and
/// Activity rows.
///
/// The selected label is `onAccent`, not `textPrimary`: `textPrimary` on the
/// rust fill was 2.68:1 in light. The visible chip stays about 38pt tall; the
/// tappable area is 44pt.
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
        }
        .buttonStyle(LiftChipStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LiftChipStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = !isSelected ? .clear : (isEnabled ? Theme.accent : Theme.accentMuted)
        let text: Color = !isSelected ? Theme.textSecondary : (isEnabled ? Theme.onAccent : Theme.textPrimary)
        return configuration.label
            .font(Theme.control.weight(.bold))
            .foregroundStyle(text)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: Theme.chipRadius)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.chipRadius)
                            .stroke(isSelected ? .clear : Theme.hairline, lineWidth: 1)
                    }
            }
            .opacity(configuration.isPressed ? 0.75 : (isEnabled || isSelected ? 1 : 0.5))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
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
///
/// VoiceOver hears "selected" on the current tab, and the row is announced as
/// a tab bar. Top-level app sections belong in a system `TabView`; this row is
/// for in-screen section switching.
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
                    // 600 weight with 1.2pt of tracking, from `nav button` in
                    // the web build's stylesheet. Subheadline, so it scales.
                    .font(Theme.control)
                    .tracking(1.2)
                    .foregroundStyle(isSelected ? Theme.accentText : Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(isSelected ? Theme.accent : .clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Text(label)
        }
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
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
    }
}

/// A filled accent pill — the browser build's default `button`.
///
/// The native apps had been rendering primary actions as bare accent-coloured
/// text ("Set my goal"), which reads as a link and is easy to miss next to the
/// web's filled pill.
///
/// Disabled, the fill drops to `accentMuted` with a `textPrimary` label.
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
        }
        .buttonStyle(LiftButtonStyle(isGhost: isGhost))
    }
}

private struct LiftButtonStyle: ButtonStyle {
    let isGhost: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let text: Color = isGhost ? Theme.textPrimary : (isEnabled ? Theme.onAccent : Theme.textPrimary)
        let fill: Color = isGhost ? .clear : (isEnabled ? Theme.accent : Theme.accentMuted)
        return configuration.label
            .font(Theme.control)
            .foregroundStyle(text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background {
                Capsule()
                    .fill(fill)
                    .overlay { Capsule().stroke(isGhost ? Theme.hairline : .clear, lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.75 : (isGhost && !isEnabled ? 0.5 : 1))
            .contentShape(Capsule())
    }
}

/// Label and value side by side, stacked instead when the text is too large
/// to fit on one line (accessibility text sizes).
private struct LabelValueLayout<Label: View, Value: View>: View {
    @ViewBuilder let label: Label
    @ViewBuilder let value: Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                label
                Spacer(minLength: 8)
                value
            }
            VStack(alignment: .leading, spacing: 2) {
                label
                value
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Label left, value right, with a full-width progress rule beneath —
/// the macro rows on the Home tab. VoiceOver reads it as one element:
/// "Protein, 120 of 200 g".
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
        guard goal > 0, current.isFinite, goal.isFinite else { return 0 }
        return max(0, min(current / goal, 1))
    }

    /// Whole numbers, through the guarded formatter: `Int(_:)` traps on NaN,
    /// infinity and past Int.max.
    private static func whole(_ value: Double) -> String {
        CookFormat.trimmed(value.isFinite ? value.rounded(.towardZero) : value)
    }

    public var body: some View {
        VStack(spacing: 6) {
            LabelValueLayout {
                Text(label)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            } value: {
                Text("\(Self.whole(current)) / \(Self.whole(goal)) \(unit)")
                    .font(Theme.body)
                    .foregroundStyle(Theme.accentText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline.opacity(0.5))
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Self.whole(current)) of \(Self.whole(goal)) \(unit)")
    }
}

/// Plain label/value row — the "Fuel so far today" list. One VoiceOver
/// element: "Protein, 120 g".
public struct StatRow: View {
    let label: String
    let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        LabelValueLayout {
            Text(label).font(Theme.body).foregroundStyle(Theme.textPrimary)
        } value: {
            Text(value).font(Theme.body).foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A card's fill, plus the hairline it needs in light.
    ///
    /// For cards drawn without `LiftCard`. Both apps had over twenty of them
    /// spelled `.background(Theme.surface, in: .rect(cornerRadius:))`, which in
    /// light left them borderless beside `LiftCard`'s outlined ones -- the same
    /// kind of card looking two different ways on adjacent screens.
    public func liftCardBackground() -> some View {
        self
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.cardBorder, lineWidth: 1)
            }
    }

    /// Applies the page background and default text colour.
    ///
    /// `.scrollBounceBehavior(.always)` is deliberate: without it a ScrollView
    /// whose content fits the screen is completely inert, which is
    /// indistinguishable from broken scrolling.
    public func liftScreen() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollBounceBehavior(.always)
            .tint(Theme.screenTint)
            .foregroundStyle(Theme.textPrimary)
    }
}
