import XCTest
@testable import LiftMapCore

final class DownloadCancelTests: XCTestCase {
    private let id = UUID()

    /// The update case the rule exists for: the host already deleted the old
    /// area on `onDone(area)`, so deleting the new one would lose both.
    func testACancelAfterTheDownloadWasHandedOverDeletesNothing() {
        XCTAssertEqual(DownloadCancel.decide(finished: true, cancelling: false, sheetBeganArea: true, areaID: id),
                       .ignore)
        XCTAssertEqual(DownloadCancel.decide(finished: true, cancelling: false, sheetBeganArea: false, areaID: id),
                       .ignore)
    }

    func testASecondCancelDoesNothing() {
        XCTAssertEqual(DownloadCancel.decide(finished: false, cancelling: true, sheetBeganArea: true, areaID: id),
                       .ignore)
    }

    func testAnAreaTheSheetBeganIsDeletedThenClosed() {
        XCTAssertEqual(DownloadCancel.decide(finished: false, cancelling: false, sheetBeganArea: true, areaID: id),
                       .deleteThenClose(id))
    }

    func testARetriedAreaIsKept() {
        XCTAssertEqual(DownloadCancel.decide(finished: false, cancelling: false, sheetBeganArea: false, areaID: id),
                       .close)
    }

    func testNothingBegunJustCloses() {
        XCTAssertEqual(DownloadCancel.decide(finished: false, cancelling: false, sheetBeganArea: true, areaID: nil),
                       .close)
    }
}
