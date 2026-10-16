#if DEBUG
import Foundation
import LarderCore

/// Sample shelves for previews.
enum PreviewData {
    static func items(now: Date = .now) -> [PantryItem] {
        func day(_ offset: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now
        }
        return [
            PantryItem(rawName: "Spinach", quantityGrams: 200, location: .fridge, bestBy: day(0), source: .manual, addedOn: now),
            PantryItem(rawName: "Yoghurt", quantityGrams: 500, location: .fridge, bestBy: day(2), source: .manual, addedOn: now),
            PantryItem(rawName: "Chicken thighs", quantityGrams: 900, location: .freezer, bestBy: day(40), source: .barcode, addedOn: now),
            PantryItem(rawName: "Rice", quantityGrams: 1_000, location: .pantry, source: .manual, addedOn: now),
            PantryItem(rawName: "Milk", quantityGrams: 1_000, location: .fridge, bestBy: day(-1), source: .manual, addedOn: now),
            PantryItem(rawName: "Lentils", quantityGrams: 750, location: .pantry, bestBy: day(120), source: .manual, addedOn: now),
        ]
    }

    @MainActor
    static func model(items: [PantryItem] = [], pendingLines: [DraftLine] = []) -> ShelvesModel {
        let model = ShelvesModel(
            pantry: FakePantryRepository(items: items),
            foods: FakeFoodRepository(),
            assistant: FakeAssistant(),
            dates: FixedDateProvider(.now)
        )
        model.pendingLines = pendingLines
        return model
    }
}
#endif
