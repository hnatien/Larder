import Testing
@testable import FeatureRecipes

struct TimerDetectorTests {
    @Test(arguments: [
        ("Simmer for 10 minutes.", 600),
        ("Bake 1 hour", 3600),
        ("Stir for 45 secs", 45),
        ("Cook 8-10 minutes", 600),
        ("Cook 8 to 10 minutes", 600),
        ("Cook 8\u{2013}10 minutes", 600),
        ("Bake 1 hour 20 minutes", 4800),
        ("Rest for 1 hour and 30 minutes", 5400),
        ("Simmer 5 minutes, then rest 10 minutes", 300),
        ("Roast 1.5 hours", 5400),
        ("Wait 30 SECONDS", 30),
        ("Bake for 2 hrs", 7200),
        ("Grill 2 min per side", 120),
        ("Whisk for 90 sec", 90),
    ] as [(String, Int)])
    func findsDuration(text: String, expected: Int) {
        #expect(TimerDetector.seconds(in: text) == expected)
    }

    @Test(arguments: [
        "Chop the onion", "Heat the oven to 200 degrees", "Serves 4 people", "Cook for 0 minutes", "Add 2 tablespoons of oil", "",
    ])
    func findsNothing(text: String) {
        #expect(TimerDetector.seconds(in: text) == nil)
    }
}

struct DurationFormatTests {
    @Test(arguments: [
        ("PT1H20M", 80), ("PT30M", 30), ("PT45S", 1), ("P0DT30M", 30), ("P1DT2H", 1560), ("PT1.5H", 90), ("pt15m", 15), ("P1W", 10080),
    ] as [(String, Int)])
    func readsIsoDuration(text: String, expected: Int) {
        #expect(ISO8601Duration.minutes(from: text) == expected)
    }

    @Test(arguments: ["", "garbage", "PT", "PT0S", "P1Y", "PT5", "30 minutes"])
    func rejectsNonDurations(text: String) {
        #expect(ISO8601Duration.minutes(from: text) == nil)
    }

    @Test func clockFormat() {
        #expect(TimerFormat.clock(0) == "00:00")
        #expect(TimerFormat.clock(65) == "01:05")
        #expect(TimerFormat.clock(600) == "10:00")
        #expect(TimerFormat.clock(3725) == "1:02:05")
        #expect(TimerFormat.clock(-4) == "00:00")
    }

    @Test func spokenFormatNamesTheTime() {
        let spoken = TimerFormat.spoken(65)
        #expect(spoken.contains("1"))
        #expect(spoken.contains("5"))
    }
}
