#if canImport(AppKit)
import AppKit
#endif
import Foundation
import LarderCore
import Testing
@testable import LarderDesign

private let bannedWords = ["good", "bad", "clean", "cheat"]

/// Every Copy string, with sample arguments for the ones that take them.
private let allCopy: [String] = [
    Copy.Tab.tonight, Copy.Tab.ledger, Copy.Tab.shelves, Copy.Tab.recipes, Copy.Tab.grocery, Copy.Tab.account,
    Copy.Action.swap, Copy.Action.skip, Copy.Action.markCooked, Copy.Action.letItGo, Copy.Action.eatIt,
    Copy.Action.notNow, Copy.Action.addWhatYouHave, Copy.Action.planMyWeek, Copy.Action.otherIdeas, Copy.Action.addFood,
    Copy.Freshness.fresh, Copy.Freshness.soon, Copy.Freshness.today, Copy.Freshness.past,
    Copy.Freshness.spoken(word: "Use soon", bestBy: "14 October"),
    Copy.Shelf.light, Copy.Shelf.comfortable, Copy.Shelf.heavy,
    Copy.Ledger.today, Copy.Ledger.minutes(25), Copy.Ledger.spokenMinutes(25), Copy.Ledger.spokenMinutes(1),
    Copy.Allergen.checkTheLabel,
    Copy.Allergen.excluded(allergen: "peanut", because: "ingredient list"),
    Copy.Allergen.unsure(about: "the stock cube"),
    Copy.Medical.disclaimer,
    Copy.Plus.name, Copy.Plus.pitch, Copy.Plus.subscribe, Copy.Plus.restore,
    Copy.Voice.emptyPantry, Copy.Voice.firstPlan(nights: 2, using: "spinach"), Copy.Voice.firstPlan(nights: 1, using: "spinach"),
    Copy.Voice.expiring(item: "Spinach", weekday: "Thursday"), Copy.Voice.expiredToday(item: "yoghurt"),
    Copy.Voice.leftoverTag(dish: "Chilli", day: 2, of: 4), Copy.Voice.lightOnGroup("greens"),
    Copy.Voice.vetoReply, Copy.Voice.planSaved, Copy.Voice.offline,
] + FoodGroup.allCases.map { Copy.Shelf.name(of: $0) }

private func catalogueStrings() throws -> [String: String] {
    let data = try Data(contentsOf: DesignSources.catalogue)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: [String: Any]])
    return strings.mapValues { entry in
        let english = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any]
        let unit = english?["stringUnit"] as? [String: String]
        return unit?["value"] ?? String(describing: english ?? [:])
    }
}

@Suite("Copy")
struct CopyTests {
    @Test func noExclamationMarks() {
        for string in allCopy { #expect(!string.contains("!"), "\(string)") }
    }

    @Test func noEmDashes() {
        for string in allCopy { #expect(!string.contains("\u{2014}"), "\(string)") }
    }

    @Test func noBannedWords() {
        for string in allCopy {
            for word in bannedWords { #expect(!string.lowercased().contains(word), "\(word) in \(string)") }
        }
    }

    @Test func noStringIsEmptyOrUnresolved() {
        for string in allCopy {
            #expect(!string.isEmpty)
            #expect(!string.contains("%"), "unresolved format in \(string)")
        }
    }

    @Test func catalogueStringsFollowTheSameRules() throws {
        let strings = try catalogueStrings()
        #expect(strings.count > 40)
        for (key, value) in strings {
            for text in [key, value] {
                #expect(!text.contains("!"), "\(text)")
                #expect(!text.contains("\u{2014}"), "\(text)")
                for word in bannedWords { #expect(!text.lowercased().contains(word), "\(word) in \(text)") }
            }
        }
    }

    /// `Copy.swift` and every feature module source: the files whose literals are the catalogue's keys.
    private static func copySources() throws -> [String] {
        let files = [DesignSources.module.appending(path: "Tokens/Copy.swift")]
            + DesignSources.features.flatMap { DesignSources.files(withExtension: "swift", under: $0) }
        return try files.map(DesignSources.text)
    }

    @Test func catalogueKeysMatchTheLiteralsInCopy() throws {
        let literal = try NSRegularExpression(pattern: #"String\(\s*localized:\s*"((?:[^"\\]|\\.)*)""#)
        let interpolation = try NSRegularExpression(pattern: #"\\\((\w+)\)"#)
        // Interpolations are plain identifiers; these names are always integers, every other name is a string.
        let integerArguments: Set<String> = ["count", "nights", "day", "total", "minutes", "number", "step"]
        var keys = Set<String>()
        for source in try Self.copySources() {
            let range = NSRange(source.startIndex..., in: source)
            for match in literal.matches(in: source, range: range) {
                var key = String(source[try #require(Range(match.range(at: 1), in: source))])
                let spans = interpolation.matches(in: key, range: NSRange(key.startIndex..., in: key))
                for span in spans.reversed() {
                    let name = String(key[try #require(Range(span.range(at: 1), in: key))])
                    key.replaceSubrange(try #require(Range(span.range, in: key)), with: integerArguments.contains(name) ? "%lld" : "%@")
                }
                keys.insert(key)
            }
        }
        let plain = Set(try catalogueStrings().keys)
        #expect(keys.count > 40)
        #expect(keys.subtracting(plain).isEmpty, "missing from the catalogue: \(keys.subtracting(plain))")
        #expect(plain.subtracting(keys).isEmpty, "unused in Copy: \(plain.subtracting(keys))")
    }

    @Test func featureStringsResolveThroughTheCatalogue() throws {
        let local = try Regex(#"String\(\s*localized:\s*"(?:[^"\\]|\\.)*"\s*\)"#)
        let bundled = try Regex(#"String\(\s*localized:\s*"(?:[^"\\]|\\.)*",\s*bundle:\s*Copy\.bundle\s*\)"#)
        let sources = DesignSources.features.flatMap { DesignSources.files(withExtension: "swift", under: $0) }
        #expect(sources.count > 40)
        var bundledCount = 0
        for url in sources {
            let text = try DesignSources.text(url)
            #expect(text.matches(of: local).isEmpty, "\(url.lastPathComponent) has a string outside the catalogue")
            bundledCount += text.matches(of: bundled).count
        }
        #expect(bundledCount > 300)
    }

    @Test func specifiedStringsAreExact() {
        #expect(Copy.Allergen.checkTheLabel == "Check the label on every product.")
        #expect(Copy.Allergen.excluded(allergen: "peanut", because: "ingredient list") == "Excluded: contains peanut (ingredient list).")
        #expect(Copy.Allergen.unsure(about: "the stock") == "We're not sure about the stock here. Check the label.")
        #expect(Copy.Medical.disclaimer == "Larder helps you plan meals. It is not medical advice. Talk to your clinician about any condition.")
        #expect(Copy.Plus.pitch == "Planning one week is free. Larder Plus plans the month and watches your shelf.")
        #expect(Copy.Voice.planSaved == "Stamped. The week is yours.")
        #expect(Copy.Voice.vetoReply == "Fair. Here's another that uses the same ingredients.")
        #expect(Copy.Voice.offline == "Couldn't reach the server. Your plan is saved here and will sync later.")
        #expect(Copy.Voice.emptyPantry == "Add what you have at home and Larder plans dinners around it.")
        #expect(Copy.Voice.expiring(item: "Spinach", weekday: "Thursday") == "Spinach is best by Thursday. Dinner tonight uses it.")
        #expect(Copy.Voice.expiredToday(item: "yoghurt") == "The yoghurt is at its limit today. Eat it, or let it go.")
        #expect(Copy.Voice.lightOnGroup("greens") == "Light on greens this week. A handful in two dinners would do it.")
        #expect(Copy.Voice.leftoverTag(dish: "Chilli", day: 2, of: 4) == "Chilli, day 2 of 4")
    }

    @Test func tabsAndActionsAreExact() {
        #expect([Copy.Tab.tonight, Copy.Tab.ledger, Copy.Tab.shelves, Copy.Tab.recipes, Copy.Tab.grocery, Copy.Tab.account]
            == ["Tonight", "Plan", "Pantry", "Recipes", "Groceries", "Settings"])
        #expect([Copy.Action.swap, Copy.Action.skip, Copy.Action.markCooked, Copy.Action.letItGo, Copy.Action.eatIt,
                 Copy.Action.notNow, Copy.Action.addWhatYouHave, Copy.Action.planMyWeek, Copy.Action.otherIdeas, Copy.Action.addFood]
            == ["Swap", "Skip", "Mark as cooked", "Throw away", "Used up", "Not now", "Add what you have", "Plan my week",
                "Show other ideas", "Add food"])
    }

    @Test func pluralsResolveThroughTheCatalogue() {
        #expect(Copy.Ledger.spokenMinutes(1) == "1 minute")
        #expect(Copy.Ledger.spokenMinutes(25) == "25 minutes")
        #expect(Copy.Voice.firstPlan(nights: 1, using: "spinach") == "Here's your week. One night uses up the spinach.")
        #expect(Copy.Voice.firstPlan(nights: 2, using: "spinach") == "Here's your week. 2 nights use up the spinach.")
    }

    @Test func shelfWordsContainNoNumbers() {
        for word in [Copy.Shelf.light, Copy.Shelf.comfortable, Copy.Shelf.heavy] {
            #expect(word.rangeOfCharacter(from: .decimalDigits) == nil)
        }
    }

    @Test func everyFoodGroupHasADistinctName() {
        let names = FoodGroup.allCases.map { Copy.Shelf.name(of: $0) }
        #expect(Set(names).count == FoodGroup.allCases.count)
    }
}

@Suite("FreshnessStyle")
struct FreshnessStyleTests {
    @Test func wordsAreTheSpecifiedFour() {
        #expect(FreshnessStyle.Level.allCases.map { FreshnessStyle($0).word } == ["Fresh", "Use soon", "Use today", "Past its best"])
    }

    @Test func everyWordHasAnSFSymbol() {
        for level in FreshnessStyle.Level.allCases {
            let style = FreshnessStyle(level)
            #expect(!style.word.isEmpty)
            #expect(!style.symbol.isEmpty, "\(style.word) has no symbol")
        }
    }

    @Test func symbolsAreDistinctSoLevelsDifferWithoutColour() {
        let symbols = FreshnessStyle.Level.allCases.map { FreshnessStyle($0).symbol }
        #expect(Set(symbols).count == symbols.count)
    }

    #if canImport(AppKit)
    @Test func symbolsExistInTheSystemSet() {
        for level in FreshnessStyle.Level.allCases {
            let style = FreshnessStyle(level)
            #expect(NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil) != nil, "\(style.symbol)")
        }
    }
    #endif
}

@Suite("FreshnessStamp dates")
struct FreshnessStampDateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
    private let locale = Locale(identifier: "en_GB")
    /// Saturday 17 October 2026, mid-morning.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10)) ?? .now }

    private func text(daysFromNow days: Int) -> String {
        let date = calendar.date(byAdding: .day, value: days, to: now) ?? now
        return FreshnessStamp.dateText(date, now: now, calendar: calendar, locale: locale)
    }

    @Test func nearDatesReadAsWords() {
        #expect(text(daysFromNow: 0) == "Today")
        #expect(text(daysFromNow: 1) == "Tomorrow")
        #expect(text(daysFromNow: -1) == "Yesterday")
        #expect(text(daysFromNow: 3) == "In 3 days")
        #expect(text(daysFromNow: -2) == "2 days ago")
    }

    @Test func laterDatesShowTheDayAndTheYearOnlyWhenItDiffers() {
        #expect(text(daysFromNow: 10) == "27 Oct")
        #expect(text(daysFromNow: 90) == "15 Jan 2027")
    }
}
