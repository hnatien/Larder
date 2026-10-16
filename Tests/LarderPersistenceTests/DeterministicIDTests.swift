import Foundation
import LarderCore
import Testing
@testable import LarderPersistence

struct DeterministicIDTests {
    @Test func sameSlugAlwaysGivesTheSameIdentifier() {
        #expect(DeterministicID.uuid(for: "chicken-breast").uuidString == "8B04FCFA-BFB7-54F6-9DA0-227ECAC82D2C")
        #expect(DeterministicID.foodID(slug: "olive-oil") == DeterministicID.foodID(slug: "olive-oil"))
        #expect(DeterministicID.recipeID(slug: "chicken-breast").rawValue == DeterministicID.uuid(for: "chicken-breast"))
    }

    @Test func differentSlugsGiveDifferentIdentifiers() {
        let slugs = ["olive-oil", "olive-oils", "Olive-oil", "", "weeknight-chana-masala"]
        #expect(Set(slugs.map(DeterministicID.uuid(for:))).count == slugs.count)
        #expect(
            DeterministicID.ingredientID(recipeSlug: "soup", position: 0)
                != DeterministicID.ingredientID(recipeSlug: "soup", position: 1)
        )
    }

    @Test(arguments: ["chicken-breast", "", "jalapeño-pepper"])
    func identifiersCarryVersionFiveAndRFC4122Variant(slug: String) {
        let bytes = DeterministicID.uuid(for: slug).uuid
        #expect(bytes.6 >> 4 == 5)
        #expect(bytes.8 >> 6 == 0b10)
    }
}
