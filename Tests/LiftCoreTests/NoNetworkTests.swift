import XCTest

/// The in-house rule (LIFT superproject,
/// `docs/superpowers/specs/2026-10-06-in-house-runtime-design.md`): at runtime
/// nothing makes a request to any server. Both iPhone apps link this package,
/// so a request added here would get past both apps' own guards; this one
/// reads `Sources/LiftCore` and `Sources/LiftReference`. Comments are stripped
/// first, so prose naming an API to explain its absence does not trip it.
final class NoNetworkTests: XCTestCase {

    static let forbidden = ["URLSession", "URLRequest", "NWConnection",
                            "import Network", "import MapKit", "import WebKit"]

    static func offences(in code: String) -> [String] {
        var stripped = code.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "",
                                                 options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: "//[^\n]*", with: "",
                                                 options: .regularExpression)
        return forbidden.filter { stripped.contains($0) }
    }

    func testTheScannerCatchesCodeAndIgnoresComments() {
        XCTAssertEqual(Self.offences(in: "let s = URLSession.shared"), ["URLSession"])
        XCTAssertEqual(Self.offences(in: "// URLSession is not used here\nlet x = 1"), [])
        XCTAssertEqual(Self.offences(in: "/* import MapKit */\nimport SwiftUI"), [])
        XCTAssertEqual(Self.offences(in: "import MapKit\n"), ["import MapKit"])
    }

    func testTheKitMakesNoRequest() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var checked = 0
        var found: [String] = []
        for folder in ["Sources/LiftCore", "Sources/LiftReference"] {
            let dir = root.appendingPathComponent(folder)
            let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
            for file in files {
                checked += 1
                let code = try String(contentsOf: file, encoding: .utf8)
                found += Self.offences(in: code).map { "\(file.lastPathComponent): \($0)" }
            }
        }
        XCTAssertGreaterThan(checked, 10, "found too little source to check under \(root.path)")
        XCTAssertEqual(found, [], "a network API in the kit -- see the in-house rule")
    }
}
