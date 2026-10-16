import Testing
@testable import FeatureRecipes

struct HTMLTextTests {
    @Test func visibleTextDropsScriptsStylesCommentsAndTags() throws {
        let text = HTMLText.visibleText(from: try Fixture.html("plain-page"), limit: 20_000)
        #expect(text.contains("Grandma's stew"))
        #expect(text.contains("Serves 6 people."))
        #expect(text.contains("2 carrots"))
        #expect(text.contains("Simmer for 40 minutes."))
        #expect(!text.contains("tracking"))
        #expect(!text.contains("color: red"))
        #expect(!text.contains("comment"))
        #expect(!text.contains("photo.jpg"))
        #expect(!text.contains("<"))
    }

    @Test func blockElementsSitOnTheirOwnLines() throws {
        let text = HTMLText.visibleText(from: try Fixture.html("plain-page"), limit: 20_000)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.contains("2 carrots"))
        #expect(lines.contains("1 onion"))
    }

    @Test func visibleTextIsCapped() {
        let html = "<p>" + String(repeating: "word ", count: 10_000) + "</p>"
        let text = HTMLText.visibleText(from: html, limit: 20_000)
        #expect(text.count == 20_000)
    }

    @Test func capNeverExceedsTheLimit() {
        #expect(HTMLText.visibleText(from: "<p>Hello there</p>", limit: 5).count <= 5)
        #expect(HTMLText.visibleText(from: "", limit: 5).isEmpty)
    }

    @Test func unterminatedTagDoesNotCrash() {
        #expect(HTMLText.visibleText(from: "Hello <b", limit: 100) == "Hello")
    }

    @Test func decodesNamedAndNumericEntities() {
        #expect(HTMLText.decodeEntities("Fish &amp; chips &lt;3 &#65;&#x42; &frac12; cup") == "Fish & chips <3 AB \u{BD} cup")
        #expect(HTMLText.decodeEntities("AT&T &unknown; &") == "AT&T &unknown; &")
    }

    @Test func plainStripsMarkupToOneLine() {
        #expect(HTMLText.plain("Stir <b>well</b>.<br>Then   serve &amp; enjoy") == "Stir well. Then serve & enjoy")
    }
}
