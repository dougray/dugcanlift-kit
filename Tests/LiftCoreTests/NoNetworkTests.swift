import XCTest

/// The in-house rule (LIFT superproject,
/// `docs/superpowers/specs/2026-10-06-in-house-runtime-design.md`): at runtime
/// nothing makes a request to any server. Both iPhone apps link this package,
/// so a request added here would get past both apps' own guards; this one
/// reads `Sources/LiftCore` and `Sources/LiftReference`. Comments are stripped
/// first, so prose naming an API to explain its absence does not trip it.
final class NoNetworkTests: XCTestCase {

    static let forbidden = ["URLSession", "URLRequest", "NWConnection",
                            "import Network", "import MapKit", "import WebKit", "AsyncImage("]

    static func offences(in code: String) -> [String] {
        // Strip line comments first: a block comment opening inside a line comment (e.g. `// Sources/*`)
        // must not delete real code up to a later `*/`. Stripping line comments first can only leave
        // comment text, which fails loudly.
        var stripped = code.replacingOccurrences(of: "//[^\n]*", with: "",
                                                 options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "",
                                                 options: .regularExpression)
        return forbidden.filter { stripped.contains($0) }
    }

    func testTheScannerCatchesCodeAndIgnoresComments() {
        XCTAssertEqual(Self.offences(in: "let s = URLSession.shared"), ["URLSession"])
        XCTAssertEqual(Self.offences(in: "// URLSession is not used here\nlet x = 1"), [])
        XCTAssertEqual(Self.offences(in: "/* import MapKit */\nimport SwiftUI"), [])
        XCTAssertEqual(Self.offences(in: "import MapKit\n"), ["import MapKit"])
        // Line comments must be stripped first: a `/*` inside a line comment must not delete real code to a later `*/`.
        XCTAssertEqual(Self.offences(in: "/// reads Sources/*\nlet s = URLSession.shared\n/* note */"), ["URLSession"])
        XCTAssertEqual(Self.offences(in: "AsyncImage(url: u)"), ["AsyncImage("])
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
            XCTAssertGreaterThan(files.count, 0, "folder \(folder) must have at least one Swift file")
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
