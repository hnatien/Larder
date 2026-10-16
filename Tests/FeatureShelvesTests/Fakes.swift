import Foundation
import LarderCore
import Testing

@testable import FeatureShelves

/// Shared fixtures. The in-memory fakes (`FakePantryRepository`, `FakeFoodRepository`, `FakeAssistant`,
/// `FixedDateProvider`) live in `Sources/FeatureShelves/Preview/PreviewFakes.swift` so previews can use them too.
enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 16 October 2026, 12:00 UTC.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12)) ?? .distantPast

    /// The moment `days` calendar days from `now`, at `hour` UTC.
    static func date(days: Int, hour: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    static func item(
        _ name: String,
        grams: Double = 100,
        location: StorageLocation = .pantry,
        bestByDays: Int? = nil,
        foodID: FoodID? = nil
    ) -> PantryItem {
        PantryItem(
            foodID: foodID,
            rawName: name,
            quantityGrams: grams,
            location: location,
            bestBy: bestByDays.map { date(days: $0) },
            source: .manual,
            addedOn: now
        )
    }

    static func food(_ name: String, density: Double? = nil, portions: [Portion] = []) -> Food {
        Food(name: name, source: .seedApproximate, portions: portions, foodGroup: .grains, densityGPerMl: density)
    }

    @MainActor
    static func model(
        items: [PantryItem] = [],
        foods: [Food] = [],
        assistant: FakeAssistant = FakeAssistant()
    ) -> (model: ShelvesModel, pantry: FakePantryRepository, assistant: FakeAssistant) {
        let pantry = FakePantryRepository(items: items)
        let model = ShelvesModel(
            pantry: pantry,
            foods: FakeFoodRepository(foods: foods),
            assistant: assistant,
            dates: FixedDateProvider(now),
            calendar: calendar
        )
        return (model, pantry, assistant)
    }

    @MainActor
    static func loadedModel(items: [PantryItem], foods: [Food] = []) async -> ShelvesModel {
        let model = Fixture.model(items: items, foods: foods).model
        await model.load()
        return model
    }
}
