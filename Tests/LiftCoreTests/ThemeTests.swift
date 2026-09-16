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
    #endif

    func testSystemIsTheDefaultAndHandsControlBack() {
        XCTAssertEqual(AppAppearance(rawValue: "unknown") ?? .system, .system)
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }
}
