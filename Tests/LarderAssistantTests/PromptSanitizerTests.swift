import Foundation
import Testing
import LarderCore
@testable import LarderAssistant

struct PromptSanitizerTests {
    private let sanitizer = PromptSanitizer()

    @Test(arguments: ["cook@example.com", "first.last+larder@mail.example.co.uk"])
    func emailsAreRemoved(email: String) {
        #expect(sanitizer.scrub("write to \(email) today") == "write to [removed] today")
    }

    @Test(arguments: ["+44 20 7946 0958", "+1 (555) 123-4567", "+33 6 12 34 56 78", "(555) 123-4567", "020 7946 0958", "+49-30-901820", "555.123.4567"])
    func phoneNumbersAreRemoved(phone: String) {
        #expect(sanitizer.scrub("call \(phone) after six") == "call [removed] after six")
    }

    @Test(arguments: ["https://example.com/recipes?id=4", "http://example.com", "www.example.com/dal"])
    func urlsAreRemoved(url: String) {
        #expect(sanitizer.scrub("from \(url) yesterday") == "from [removed] yesterday")
    }

    @Test(arguments: ["4111111111111111", "4111 1111 1111 1111", "4111-1111-1111-1111"])
    func cardNumbersAreRemoved(card: String) {
        #expect(sanitizer.scrub("card \(card) thanks") == "card [removed] thanks")
    }

    @Test(arguments: [
        "2 onions, 500 g chicken",
        "Bake 20-25 minutes at 180 C",
        "Serves 4 to 6, 1 1/2 cups stock",
        "From 2020-2024 we cooked 350 meals",
        "Simmer 10.30 to 11.45",
    ])
    func everydayNumbersAreKept(text: String) {
        #expect(sanitizer.scrub(text) == text)
    }

    @Test func limitCountsUTF16AndNeverSplitsACharacter() {
        let text = "  " + String(repeating: "a", count: 498) + "🍅🍅"
        let scrubbed = sanitizer.scrub(text, limit: sanitizer.pantryLimit)
        #expect(scrubbed.utf16.count == 500)
        #expect(scrubbed.hasSuffix("a🍅"))
        #expect(sanitizer.scrub("   ", limit: 10).isEmpty)
    }

    @Test func defaultLimitsMatchTheProxy() {
        #expect(sanitizer.pantryLimit == 500)
        #expect(sanitizer.recipeLimit == 20_000)
        #expect(sanitizer.instructionLimit == 300)
        let custom = PromptSanitizer(pantryLimit: 10)
        #expect(custom.scrub("2 onions and rice", limit: custom.pantryLimit) == "2 onions a")
    }

    @Test func profileSummaryCarriesExactlyFourFields() throws {
        let summary = ProfileSummary.make(profile: Fixtures.profile, constraints: Fixtures.sensitiveConstraints)
        #expect(summary == ProfileSummary(goal: .lessWaste, householdSize: 3, maxCookMinutes: 30, showsNumbers: false))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        #expect(Set(object.keys) == ["goal", "householdSize", "maxCookMinutes", "showsNumbers"])
    }

    @Test func profileSummaryClampsToTheProxyRanges() {
        var profile = Fixtures.profile
        profile.householdSize = 0
        profile.maxCookMinutes = 1000
        let low = ProfileSummary.make(profile: profile, constraints: [])
        #expect(low.householdSize == 1)
        #expect(low.maxCookMinutes == 480)
        profile.householdSize = 40
        profile.maxCookMinutes = 1
        let high = ProfileSummary.make(profile: profile, constraints: [])
        #expect(high.householdSize == 12)
        #expect(high.maxCookMinutes == 5)
    }
}
