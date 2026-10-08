import XCTest
import SwiftUI
@testable import LiftCore
#if canImport(AppKit)
import AppKit
#endif

/// Pins the palette in both appearances. The web's CSS and Android's
/// DclPalette copy these values, so a token that drifts here drifts from them.
final class ThemeTests: XCTestCase {

    #if canImport(AppKit)
    private func hex(_ color: Color, dark: Bool) -> String {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        var out = ""
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let resolved = NSColor(color).usingColorSpace(.sRGB)!
            if resolved.alphaComponent == 0 { out = "clear"; return }
            out = String(format: "%02X%02X%02X",
                         Int((resolved.redComponent * 255).rounded()),
                         Int((resolved.greenComponent * 255).rounded()),
                         Int((resolved.blueComponent * 255).rounded()))
        }
        return out
    }

    func testDarkIsUnchanged() {
        XCTAssertEqual(hex(Theme.background, dark: true), "1C1B19")
        XCTAssertEqual(hex(Theme.surface, dark: true), "242220")
        XCTAssertEqual(hex(Theme.accent, dark: true), "C1442C")
        XCTAssertEqual(hex(Theme.textPrimary, dark: true), "EDE7DD")
        XCTAssertEqual(hex(Theme.textSecondary, dark: true), "A39C8E")
        XCTAssertEqual(hex(Theme.hairline, dark: true), "3A3733")
        XCTAssertEqual(hex(Theme.cardBorder, dark: true), "clear", "dark cards never had a border")
    }

    /// `liftScreen()` tints with rust-as-text, not the fill rust: tinted text
    /// buttons were 3.39:1 in dark with `accent`. Light is unchanged.
    func testScreenTintIsTheReadableRust() {
        XCTAssertEqual(hex(Theme.screenTint, dark: true), "E0674D")
        XCTAssertEqual(hex(Theme.screenTint, dark: false), "B23C25")
        XCTAssertEqual(hex(Theme.screenTint, dark: false), hex(Theme.accent, dark: false),
                       "light mode must look the same as before 1.13.0")
    }

    func testTheApprovedLightPalette() {
        XCTAssertEqual(hex(Theme.background, dark: false), "F4EFE7")
        XCTAssertEqual(hex(Theme.surface, dark: false), "FFFCF7")
        XCTAssertEqual(hex(Theme.accent, dark: false), "B23C25")
        XCTAssertEqual(hex(Theme.accentSecondary, dark: false), "56664F")
        XCTAssertEqual(hex(Theme.onAccent, dark: false), "FFFAF3")
        XCTAssertEqual(hex(Theme.textPrimary, dark: false), "26221E")
        XCTAssertEqual(hex(Theme.textSecondary, dark: false), "665E52")
        XCTAssertEqual(hex(Theme.hairline, dark: false), "DCD3C5")
        XCTAssertEqual(hex(Theme.cardBorder, dark: false), "DCD3C5")
    }

    /// Every token, by the name `palette.json` uses. A token added to `Theme`
    /// must be added here and to the fixture, or `testEveryTokenIsInTheFixture`
    /// fails; the fixture is what DclPaletteTest checks Android against.
    private let tokens: [String: Color] = [
        "background": Theme.background, "surface": Theme.surface,
        "accent": Theme.accent, "accentText": Theme.accentText,
        "accentMuted": Theme.accentMuted, "accentSecondary": Theme.accentSecondary,
        "onAccent": Theme.onAccent, "textPrimary": Theme.textPrimary,
        "textSecondary": Theme.textSecondary, "hairline": Theme.hairline,
        "cardBorder": Theme.cardBorder,
    ]

    private struct Palette: Decodable {
        struct Token: Decodable { let android: String; let light: String; let dark: String? }
        let tokens: [String: Token]
        let textPairs: [[String]]
    }

    private func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "palette.json", withExtension: nil,
                                        subdirectory: "Fixtures"), "missing fixture")
    }

    private func palette() throws -> Palette {
        try JSONDecoder().decode(Palette.self, from: Data(contentsOf: fixtureURL()))
    }

    func testEveryTokenIsInTheFixture() throws {
        let fixture = try palette()
        XCTAssertEqual(Set(fixture.tokens.keys), Set(tokens.keys),
                       "Theme and palette.json disagree on which tokens exist")
        for (name, token) in fixture.tokens {
            guard let color = tokens[name] else { continue }
            XCTAssertEqual(hex(color, dark: false), token.light, "\(name) light")
            XCTAssertEqual(hex(color, dark: true), token.dark ?? "clear", "\(name) dark")
        }
    }

    /// The fixture is copied into dugcanlift-kit-android. When that checkout
    /// sits beside this one, the two copies must be identical.
    func testAndroidCopyOfTheFixtureIsIdentical() throws {
        let android = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("dugcanlift-kit-android/liftcore/src/test/resources/fixtures/palette.json")
        guard FileManager.default.fileExists(atPath: android.path) else {
            throw XCTSkip("dugcanlift-kit-android is not checked out beside this repo")
        }
        XCTAssertEqual(try Data(contentsOf: android), try Data(contentsOf: fixtureURL()),
                       "palette.json differs between the iOS and Android kits")
    }

    private func luminance(_ hex: String) -> Double {
        let v = UInt32(hex, radix: 16)!
        func lin(_ c: UInt32) -> Double {
            let x = Double(c & 0xFF) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(v >> 16) + 0.7152 * lin(v >> 8) + 0.0722 * lin(v)
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func hex(_ value: UInt32) -> String { String(format: "%06X", value) }

    /// Every text pairing passes WCAG AA in both appearances. This is the
    /// check that missed dark `accent` as text (3.12:1) and `textPrimary` on a
    /// filled chip (2.68:1).
    func testTextPairingsPassAA() throws {
        for pair in try palette().textPairs {
            let (fg, bg) = (tokens[pair[0]]!, tokens[pair[1]]!)
            for dark in [false, true] {
                let ratio = contrast(hex(fg, dark: dark), hex(bg, dark: dark))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(pair[0]) on \(pair[1]), dark \(dark)")
            }
        }
    }

    /// Under Increase Contrast: text gains well past AA, and the hairline
    /// becomes a real 3:1 boundary (WCAG 1.4.11), being the only edge of an
    /// unselected chip and a ghost button. Grounds have no high-contrast
    /// value, so the normal ones are the right comparison.
    func testIncreaseContrastValues() {
        let hc = Theme.HighContrast.self
        for (dark, grounds) in [(false, ["F4EFE7", "FFFCF7"]), (true, ["1C1B19", "242220"])] {
            for ground in grounds {
                for text in [hc.accentText, hc.textSecondary] {
                    XCTAssertGreaterThanOrEqual(contrast(hex(dark ? text.dark : text.light), ground), 6)
                }
                XCTAssertGreaterThanOrEqual(contrast(hex(dark ? hc.hairline.dark : hc.hairline.light), ground), 3)
            }
        }
    }

    func testHighContrastValuesOnlyApplyWhenAsked() {
        func r(_ dark: Bool, _ high: Bool) -> UInt32? {
            Color.resolve(light: 1, dark: nil, lightHighContrast: 3, darkHighContrast: 4,
                          isDark: dark, isHighContrast: high)
        }
        XCTAssertEqual(r(false, false), 1)
        XCTAssertNil(r(true, false), "dark: nil stays clear")
        XCTAssertEqual(r(false, true), 3)
        XCTAssertEqual(r(true, true), 4)
        XCTAssertEqual(Color.resolve(light: 1, dark: 2, lightHighContrast: nil, darkHighContrast: nil,
                                     isDark: true, isHighContrast: true), 2,
                       "no high-contrast value means the normal one")
    }
    #endif

    func testSystemIsTheDefaultAndHandsControlBack() {
        XCTAssertEqual(AppAppearance(rawValue: "unknown") ?? .system, .system)
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }
}
