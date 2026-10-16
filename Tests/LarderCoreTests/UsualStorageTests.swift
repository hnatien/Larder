import Foundation
import Testing

@testable import LarderCore

@Suite("Usual storage")
struct UsualStorageTests {
    static let byName: [(String, StorageLocation)] = [
        ("chicken breasts", .fridge),
        ("10 eggs", .fridge),
        ("whole milk", .fridge),
        ("baby spinach", .fridge),
        ("blueberries", .fridge),
        ("bag of rice", .pantry),
        ("onions", .pantry),
        ("salt", .pantry),
        ("chicken stock", .pantry),
        ("coconut milk", .pantry),
        ("peanut butter", .pantry),
        ("tinned salmon", .pantry),
        ("frozen prawns", .freezer),
        ("ice cream", .freezer),
    ]

    @Test(arguments: byName)
    func itemWordsDecideWithoutAFood(name: String, location: StorageLocation) {
        #expect(StorageLocation.usual(forItemNamed: name, food: nil) == location)
    }

    @Test func itemWordsBeatTheMatchedFood() {
        let noodles = Kitchen.food("Egg noodles, dried", group: .grains)
        #expect(StorageLocation.usual(forItemNamed: "eggs", food: noodles) == .fridge)
    }

    @Test func matchedFoodNameDecidesNext() {
        let tuna = Kitchen.food("Tuna, canned in water, drained", group: .protein, tags: [.fish])
        let peas = Kitchen.food("Peas, green, frozen", group: .produce)
        #expect(StorageLocation.usual(forItemNamed: "tuna", food: tuna) == .pantry)
        #expect(StorageLocation.usual(forItemNamed: "peas", food: peas) == .freezer)
    }

    @Test func tagsAndGroupDecideLast() {
        let trout = Kitchen.food("Trout, raw", group: .protein, tags: [.fish])
        let kefir = Kitchen.food("Kefir", group: .dairy)
        let lentils = Kitchen.food("Lentils, red, split", group: .legumes)
        #expect(StorageLocation.usual(forItemNamed: "trout", food: trout) == .fridge)
        #expect(StorageLocation.usual(forItemNamed: "kefir", food: kefir) == .fridge)
        #expect(StorageLocation.usual(forItemNamed: "lentils", food: lentils) == .pantry)
    }
}
