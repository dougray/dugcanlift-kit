import XCTest
@testable import LiftCore

/// These bytes cross a language boundary: a JavaScript web app writes the
/// same format. A Swift-only round trip proves the two halves of THIS
/// implementation agree with each other and nothing more — which is exactly
/// how two encoders in this project once disagreed about whether food macros
/// were per serving, halving users' calories for months with every test
/// green. So the interop test below decodes bytes produced elsewhere.
final class ShareLinkTests: XCTestCase {

    // MARK: - The shape that Codable synthesis would silently get wrong

    func testAWorkoutEntryEncodesAsAnArrayNotAnObject() throws {
        // `WireWorkoutEntry` reads an UNKEYED container: an Int then a nested
        // array. Its `encode(to:)` is hand-written for that reason. Without
        // it, Codable synthesis emits `{"exerciseIndex":7,"sets":[...]}` —
        // which compiles, round-trips against itself, and is unreadable by
        // every other implementation of this format.
        let entry = WireWorkoutEntry(exerciseIndex: 7, sets: [[225, 5, 8], [nil, 5]])
        let data = try JSONEncoder().encode(entry)

        let parsed = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(parsed is [Any], "encoded as a JSON object, not an array")
        XCTAssertFalse(parsed is [String: Any])

        let tuple = try XCTUnwrap(parsed as? [Any])
        XCTAssertEqual(tuple.count, 2)
        XCTAssertEqual((tuple[0] as? NSNumber)?.intValue, 7, "index must come first")
        XCTAssertNotNil(tuple[1] as? [Any], "sets must be the second element")
    }

    func testAWorkoutEntryRoundTripsIncludingItsNilWeights() throws {
        // A nil weight is a bodyweight set. It must survive as null, not
        // become zero — a zero-weight set is a different thing entirely.
        let entry = WireWorkoutEntry(exerciseIndex: 3, sets: [[nil, 12], [100, 8, 9]])
        let data = try JSONEncoder().encode(entry)
        let back = try JSONDecoder().decode(WireWorkoutEntry.self, from: data)

        XCTAssertEqual(back.exerciseIndex, 3)
        XCTAssertEqual(back.sets.count, 2)
        XCTAssertNil(back.sets[0][0])
        XCTAssertEqual(back.sets[0][1], 12)
        XCTAssertEqual(back.sets[1][0], 100)
    }

    func testTheEncodedTupleIsExactlyWhatTheDecoderReads() throws {
        // Hand-built JSON in the wire's own shape, decoded by the package.
        // If the encoder's element order ever drifts from the decoder's, the
        // previous test still passes and this one fails.
        let json = "[9,[[140,6],[null,10]]]".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WireWorkoutEntry.self, from: json)
        XCTAssertEqual(decoded.exerciseIndex, 9)
        XCTAssertEqual(decoded.sets[0][0], 140)
        XCTAssertNil(decoded.sets[1][0])

        let reEncoded = try JSONEncoder().encode(decoded)
        XCTAssertEqual(String(data: reEncoded, encoding: .utf8), "[9,[[140,6],[null,10]]]")
    }

    // MARK: - Interop with bytes this package did not produce

    func testDecodesARealFragmentProducedByTheOtherImplementation() throws {
        // Captured from LIFT iOS's own CoachShare encoder, not built here.
        // This is the only test in the file that proves interoperability
        // rather than self-consistency.
        let fragment = "1zTZDLboMwEEV_xZr1UNnmZVjSl1JVLUorZYFYGOIIBILWQNOU8u8dEimqVzP3js8dzQwlxDPUEEMRHlwtSgUIHbVPvd3rjm3NyQwkfZBU92s1UdUWsCDsIc5mKI4QSx7dePzfEwgHcjOOAl3J0eOoUEiUKPKcvJ4g6evufvu8eXjfvDwSt4GYBs7Z6TRU7E6fSB1GiJUniXe88LJMSh99VDlm0vPRxSgnZCbIEWp1QurzZU1ZF4Tbqi4b07HCGk00hF1Vj4bZujRAQ5byJJeBwwNHemSPV0E5IiLhixZD-F5ZiS4b9vY56fE30bYwbUt-YrqyYqk1w3BVCfxD30LfD873WP4A"
        let payload = try ShareLinkCodec.decode(fragment: fragment)

        XCTAssertEqual(payload.v, 1)
        XCTAssertFalse(payload.d.isEmpty)
        XCTAssertFalse(payload.x.isEmpty, "exercise dictionary should be populated")
    }

    func testRejectsAFragmentThatIsNotAShareLink() {
        XCTAssertThrowsError(try ShareLinkCodec.decode(fragment: "not-a-fragment"))
        XCTAssertThrowsError(try ShareLinkCodec.decode(fragment: ""))
    }
}
