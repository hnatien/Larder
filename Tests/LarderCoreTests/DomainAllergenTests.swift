import Foundation
import Testing
@testable import LarderCore

struct AllergenTests {
    @Test func coversUSNineAndEUFourteen() {
        #expect(Allergen.allCases.count == 15)
        #expect(Set(Allergen.allCases).count == 15)
    }

    @Test func untaggedAllergenIsUnknownNeverFree() {
        let tags = AllergenTags([.milk: .contains, .peanut: .verifiedFree])
        #expect(tags.presence(of: .milk) == .contains)
        #expect(tags.presence(of: .peanut) == .verifiedFree)
        #expect(tags.presence(of: .sesame) == .unknown)
        #expect(AllergenTags().presence(of: .egg) == .unknown)
    }

    @Test func tagsEncodeAsKeyedObject() throws {
        let data = try JSONEncoder().encode(AllergenTags([.treeNut: .mayContain]))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let entries = object?["entries"] as? [String: String]
        #expect(entries == ["treeNut": "mayContain"])
    }

    @Test func decodingUnknownAllergenFails() {
        let json = Data(#"{"entries":{"kiwi":"contains"}}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AllergenTags.self, from: json)
        }
    }
}
