import XCTest
@testable import LiftCore

/// PLAN-FORMAT.md "Sides": `b: 1` on an exercise done each side, and a sixth
/// set-tuple position whose bits 1-2 name a side.
///
/// `Fixtures/web-plan-per-side.txt` is a link Coach web's own encoder wrote
/// (dugcanlift-coach, `coach/fixtures/`, the same bytes). Never regenerate it
/// from this package: its value is that a different implementation wrote it.
final class PlanSidesTests: XCTestCase {

    private func fixture() throws -> PlanPayload {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "web-plan-per-side.txt",
                                                  withExtension: nil, subdirectory: "Fixtures"))
        let link = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fragment = String(link[link.index(after: try XCTUnwrap(link.firstIndex(of: "#")))...])
        return try PlanLinkCodec.decode(fragment: fragment, expectedLifterID: "a1b2c3d4")
    }

    func testTheFixtureDecodesWithItsSides() throws {
        let exercises = try XCTUnwrap(try fixture().w?.first?.e)
        XCTAssertEqual(exercises.map(\.b), [nil, 1, 1, nil, nil])
        XCTAssertEqual(exercises.map(\.isEachSide), [false, true, true, false, false])
        XCTAssertEqual(exercises[2].s.map(PlanSetFlags.sideBits), [nil, nil, nil, 1])
        XCTAssertEqual(exercises[3].s.map(PlanSetFlags.sideBits), [nil, nil, 2])
        XCTAssertEqual(exercises[4].s, [[nil, nil, nil, 600, 1600, 2]],
                       "interior nulls kept: the distance is not in the weight slot")
        XCTAssertEqual(exercises[4].s.map(PlanSetFlags.sideBits), [1])
        XCTAssertEqual(exercises[0].s, [[225, 5, 8], [225, 5, 8], [225, 5, 8]])
    }

    func testFlagsAreMaskedNeverCompared() {
        func side(_ flags: Double?) -> Int? { PlanSetFlags.sideBits(of: [30, 8, nil, nil, nil, flags]) }
        XCTAssertEqual(side(2), 1)
        XCTAssertEqual(side(4), 2)
        XCTAssertEqual(side(3), 1, "bit 0 is ignored")
        XCTAssertEqual(side(5), 2)
        XCTAssertNil(side(6), "3 in bits 1-2 reads as both")
        XCTAssertNil(side(0))
        XCTAssertNil(side(1))
        XCTAssertNil(side(nil))
        XCTAssertNil(side(2.5), "a non-integral flags is both")
        XCTAssertNil(PlanSetFlags.sideBits(of: [30, 8]), "no sixth position is both")
    }

    func testFlagsWrittenForASide() {
        XCTAssertEqual(PlanSetFlags.flags(sideBits: 1), 2)
        XCTAssertEqual(PlanSetFlags.flags(sideBits: 2), 4)
        XCTAssertNil(PlanSetFlags.flags(sideBits: 0))
        XCTAssertNil(PlanSetFlags.flags(sideBits: 3))
    }

    func testBReadsOneAsEachSideAndAnythingElseAsNot() throws {
        func exercise(_ b: String) throws -> PlanWorkoutExercise {
            try JSONDecoder().decode(PlanWorkoutExercise.self,
                                     from: Data(#"{"n":"Row","s":[[30,8]]\#(b)}"#.utf8))
        }
        XCTAssertTrue(try exercise(#","b":1"#).isEachSide)
        XCTAssertTrue(try exercise(#","b":1.0"#).isEachSide)
        XCTAssertFalse(try exercise("").isEachSide)
        XCTAssertFalse(try exercise(#","b":0"#).isEachSide)
        XCTAssertFalse(try exercise(#","b":2"#).isEachSide)
        // Junk costs the flag, never the plan.
        XCTAssertFalse(try exercise(#","b":"yes""#).isEachSide)
        XCTAssertFalse(try exercise(#","b":null"#).isEachSide)
        XCTAssertFalse(try exercise(#","b":[1]"#).isEachSide)
    }

    private func sorted(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        return String(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                      encoding: .utf8) ?? ""
    }

    func testEncodingOmitsBWhenNotEachSide() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = PlanWorkoutExercise(n: "Back Squat", q: "Barbell", c: nil, s: [[225, 5]])
        XCTAssertEqual(String(data: try encoder.encode(plain), encoding: .utf8),
                       #"{"n":"Back Squat","q":"Barbell","s":[[225,5]]}"#)
        let each = PlanWorkoutExercise(n: "Split Squat", q: "Dumbbell", c: "Slow down.",
                                       s: [[40, 8], [40, 8, nil, nil, nil, 2]], b: 1)
        XCTAssertEqual(String(data: try encoder.encode(each), encoding: .utf8),
                       #"{"b":1,"c":"Slow down.","n":"Split Squat","q":"Dumbbell","s":[[40,8],[40,8,null,null,null,2]]}"#)
    }

    /// Decoded and encoded again, the fixture's workouts are the same JSON
    /// Coach web wrote, key for key. (Compared with sorted keys: `JSONEncoder`
    /// does not keep key order, and every decoder reads keys by name.)
    func testTheFixtureReencodesToTheSameWorkoutJSON() throws {
        let workouts = try XCTUnwrap(try fixture().w)
        let web = #"[{"n":"Per-side A","e":[{"n":"Back Squat","q":"Barbell","s":[[225,5,8],[225,5,8],[225,5,8]]},{"n":"Single-Arm Dumbbell Row","q":"Dumbbell","b":1,"s":[[30,8],[30,8],[30,8]]},{"n":"Bulgarian Split Squat","q":"Dumbbell","b":1,"s":[[40,8],[40,8],[40,8],[40,8,null,null,null,2]],"c":"Extra set on the left."},{"n":"Dumbbell Bench Press","q":"Dumbbell","s":[[60,8],[60,8],[40,10,null,null,null,4]]},{"n":"Suitcase Carry","q":"Kettlebells","s":[[null,null,null,600,1600,2]],"c":"Left hand only."}]}]"#
        XCTAssertEqual(try sorted(JSONEncoder().encode(workouts)), try sorted(Data(web.utf8)))
    }
}
