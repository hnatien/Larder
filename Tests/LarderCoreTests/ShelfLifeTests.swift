import Foundation
import Testing
@testable import LarderCore

@Suite("Shelf life")
struct ShelfLifeTests {
    @Test func everyGroupHasADefaultForEveryPlace() {
        for group in FoodGroup.allCases {
            for place in [StorageLocation.fridge, .freezer, .pantry] {
                let days = ShelfLife.table[group]?[place]
                #expect(days != nil, "\(group) has no \(place) default")
                #expect((days ?? 0) > 0)
            }
        }
    }

    @Test(arguments: [
        (FoodGroup.protein, StorageLocation.fridge, 2),
        (.produce, .fridge, 5),
        (.dairy, .fridge, 7),
        (.legumes, .pantry, 365),
        (.grains, .pantry, 180),
        (.produce, .freezer, 240),
    ])
    func groupAndPlaceDecide(group: FoodGroup, location: StorageLocation, days: Int) {
        let food = Kitchen.food("Plain food", group: group)
        #expect(ShelfLife.days(forItemNamed: "Plain food", food: food, in: location) == days)
    }

    @Test func perishableGroupsKeepShorterChilledThanInTheFreezer() {
        for group in FoodGroup.allCases {
            let fridge = ShelfLife.table[group]?[.fridge] ?? 0
            let freezer = ShelfLife.table[group]?[.freezer] ?? 0
            #expect(fridge < freezer, "\(group) keeps longer chilled than frozen")
        }
    }

    @Test func itemWithoutAFoodKeepsLikeOther() {
        #expect(ShelfLife.days(forItemNamed: "Mystery jar", food: nil, in: .pantry) == ShelfLife.table[.other]?[.pantry])
        #expect(ShelfLife.days(forItemNamed: "Mystery jar", food: nil, in: .other) == ShelfLife.table[.other]?[.pantry])
    }

    @Test func namedExceptionsBeatTheGroup() {
        let egg = Kitchen.food("Egg, whole, raw", group: .protein, tags: [.egg])
        let bread = Kitchen.food("Bread, white, sliced", group: .grains)
        let tomatoes = Kitchen.food("Tomatoes, canned, chopped", group: .produce)
        #expect(ShelfLife.days(forItemNamed: "Eggs", food: egg, in: .fridge) == 21)
        #expect(ShelfLife.days(forItemNamed: "Bread", food: bread, in: .pantry) == 5)
        #expect(ShelfLife.days(forItemNamed: "Chopped tomatoes", food: tomatoes, in: .pantry) == 365)
        #expect(ShelfLife.days(forItemNamed: "Cheddar", food: nil, in: .fridge) == 21)
    }

    @Test func exceptionsOnlyApplyInTheirPlace() {
        let noodles = Kitchen.food("Egg noodles, dried", group: .grains)
        let bread = Kitchen.food("Bread, white, sliced", group: .grains)
        #expect(ShelfLife.days(forItemNamed: "Egg noodles", food: noodles, in: .pantry) == 180)
        #expect(ShelfLife.days(forItemNamed: "Bread", food: bread, in: .freezer) == 90)
        #expect(ShelfLife.days(forItemNamed: "Breadcrumbs", food: nil, in: .pantry) == 180)
    }

    @Test func bestByCountsWholeDaysFromTheDayAdded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let addedOn = Fixtures.date(2026, 10, 17).addingTimeInterval(18 * 3600)
        let chicken = Kitchen.food("Chicken breast, raw", group: .protein, tags: [.poultry])
        let bestBy = ShelfLife.bestBy(forItemNamed: "Chicken", food: chicken, in: .fridge, addedOn: addedOn, calendar: calendar)
        #expect(bestBy == Fixtures.date(2026, 10, 19))
    }
}
