import Foundation
import LarderDesign
import Testing

@testable import FeatureShelves

@Suite("Freshness and Eat first")
struct FreshnessTests {
    @MainActor
    private func level(days: Int?, hour: Int = 12) -> FreshnessStyle.Level {
        let model = Fixture.model().model
        var item = Fixture.item("Spinach")
        item.bestBy = days.map { Fixture.date(days: $0, hour: hour) }
        return model.freshness(for: item)
    }

    @Test @MainActor func fourDaysOutIsFresh() {
        #expect(level(days: 4) == .fresh)
    }

    @Test @MainActor func threeDaysOutIsSoon() {
        #expect(level(days: 3) == .soon)
    }

    @Test @MainActor func tomorrowIsSoon() {
        #expect(level(days: 1) == .soon)
    }

    @Test @MainActor func sameCalendarDayIsToday() {
        #expect(level(days: 0) == .today)
        #expect(level(days: 0, hour: 0) == .today)
        #expect(level(days: 0, hour: 23) == .today)
    }

    @Test @MainActor func yesterdayLateEveningIsPast() {
        #expect(level(days: -1, hour: 23) == .past)
    }

    @Test @MainActor func longGoneIsPast() {
        #expect(level(days: -30) == .past)
    }

    @Test @MainActor func noBestByIsFresh() {
        #expect(level(days: nil) == .fresh)
    }

    @Test @MainActor func eatFirstKeepsThreeDayBoundaryAndPast() async {
        let model = await Fixture.loadedModel(items: [
            Fixture.item("Day four", bestByDays: 4),
            Fixture.item("Day three", bestByDays: 3),
            Fixture.item("Today", bestByDays: 0),
            Fixture.item("Yesterday", bestByDays: -1),
            Fixture.item("No date"),
        ])
        #expect(model.eatFirst.map(\.rawName) == ["Yesterday", "Today", "Day three"])
    }

    @Test @MainActor func eatFirstSortsBySoonestBestBy() async {
        let model = await Fixture.loadedModel(items: [
            Fixture.item("C", bestByDays: 2),
            Fixture.item("A", bestByDays: -5),
            Fixture.item("B", bestByDays: 0),
        ])
        #expect(model.eatFirst.map(\.rawName) == ["A", "B", "C"])
    }

    @Test @MainActor func eatFirstBreaksTiesByName() async {
        let model = await Fixture.loadedModel(items: [
            Fixture.item("Yoghurt", bestByDays: 1),
            Fixture.item("Apples", bestByDays: 1),
        ])
        #expect(model.eatFirst.map(\.rawName) == ["Apples", "Yoghurt"])
    }

    @Test @MainActor func eatFirstIsEmptyWhenEverythingIsFresh() async {
        let model = await Fixture.loadedModel(items: [Fixture.item("Rice"), Fixture.item("Lentils", bestByDays: 90)])
        #expect(model.eatFirst.isEmpty)
    }
}
