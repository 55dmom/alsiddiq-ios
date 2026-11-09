import XCTest
@testable import AlSiddiq

/// v3.9: Friday is a rest day (no record on a Friday; records run Saturday to Thursday).
final class RestDayTests: XCTestCase {
    private func d(_ s: String) -> Date { Days.parse(s)! }

    func testFridayIsRestAndThursdayIsNot() {
        XCTAssertTrue(RestDay.isRest(d("2026-11-13")))    // a Friday
        XCTAssertFalse(RestDay.isRest(d("2026-11-12")))   // a Thursday
        XCTAssertFalse(RestDay.isRest(d("2026-11-14")))   // a Saturday
    }

    func testOnFridayTheSheetOpensOnThursday() {
        XCTAssertEqual(Days.iso(RestDay.lastWorkDayOnOrBefore(d("2026-11-13"))), "2026-11-12")
        XCTAssertEqual(Days.iso(RestDay.lastWorkDayOnOrBefore(d("2026-11-14"))), "2026-11-14")
    }

    func testPreviousAndNextSkipFriday() {
        XCTAssertEqual(Days.iso(RestDay.prevWorkDay(d("2026-11-14"))), "2026-11-12")   // Saturday back to Thursday
        XCTAssertEqual(Days.iso(RestDay.nextWorkDay(d("2026-11-12"), today: d("2026-11-20"))!), "2026-11-14") // Thursday forward to Saturday
        XCTAssertNil(RestDay.nextWorkDay(d("2026-11-12"), today: d("2026-11-12")))   // nothing after today
    }

    func testTimesReadHHmm() {
        XCTAssertEqual(HM.clean("07:45:00"), "07:45")
        XCTAssertEqual(HM.clean("13:10"), "13:10")
        XCTAssertNil(HM.clean(nil))
        XCTAssertEqual(HM.parts("07:45").map { "\($0.0):\($0.1)" }, "7:45")
    }
}
