import Foundation
import Testing
@testable import LarderAssistant

struct BestByHintTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    private static let britain = Locale(identifier: "en_GB")
    private static let america = Locale(identifier: "en_US")

    /// 2026-10-16T09:00:00Z, a Friday.
    private static let now = Fixtures.now

    private func date(_ hint: String?, locale: Locale = britain) -> Date? {
        BestByHint.date(from: hint, now: Self.now, calendar: Self.calendar, locale: locale)
    }

    @Test(arguments: [
        ("today", 16), ("use tonight", 16), ("tomorrow", 17), ("exp in 3 days", 19), ("5 days", 21),
        ("use soon", 19), ("next week", 23), ("best by Friday", 16), ("exp sat", 17), ("use by Tues", 20),
        ("Best before 2026-10-30", 30), ("bb 25 Oct", 25), ("use by October 28th", 28),
    ])
    func wordingBecomesADay(hint: String, day: Int) {
        #expect(date(hint) == Fixtures.date(2026, 10, day))
    }

    @Test func numericDatesFollowTheLocaleOrder() {
        #expect(date("best by 12/11", locale: Self.britain) == Fixtures.date(2026, 11, 12))
        #expect(date("best by 12/11", locale: Self.america) == Fixtures.date(2026, 12, 11))
        #expect(date("use by 11.12.26", locale: Self.britain) == Fixtures.date(2026, 12, 11))
    }

    @Test func aNumericDateOnlyValidTheOtherWayRoundIsReadThatWay() {
        #expect(date("exp 25/12", locale: Self.america) == Fixtures.date(2026, 12, 25))
    }

    @Test func aDateWithoutAYearAMonthPastMeansNextYear() {
        #expect(date("best by 1 Feb") == Fixtures.date(2027, 2, 1))
        #expect(date("best by 10 Oct") == Fixtures.date(2026, 10, 10))
    }

    @Test(arguments: [nil, "", "   ", "check the lid", "fresh", "31/02", "best by 2026-02-30", "12.50"])
    func wordingWithNoDayIsNil(hint: String?) {
        #expect(date(hint) == nil)
    }
}
