import Testing
@testable import LarderOnDeviceAI

struct ContextGuardTests {
    @Test(arguments: [(4096, 2867), (8192, 5734), (10, 7), (0, 0), (-1, 0)])
    func budgetIsSeventyPercentOfTheWindow(contextSize: Int, budget: Int) {
        #expect(ContextGuard.budget(contextSize: contextSize) == budget)
    }

    @Test func requestsWithinBudgetAreSent() {
        #expect(ContextGuard.decision(inputTokens: 0, contextSize: 4096) == .send)
        #expect(ContextGuard.decision(inputTokens: 2867, contextSize: 4096) == .send)
    }

    @Test func requestsOverBudgetButInsideTheWindowAreTruncated() {
        #expect(ContextGuard.decision(inputTokens: 2868, contextSize: 4096) == .truncate)
        #expect(ContextGuard.decision(inputTokens: 4095, contextSize: 4096) == .truncate)
    }

    @Test func requestsFillingTheWindowOrWithBadSizesAreRejected() {
        #expect(ContextGuard.decision(inputTokens: 4096, contextSize: 4096) == .reject)
        #expect(ContextGuard.decision(inputTokens: 50_000, contextSize: 8192) == .reject)
        #expect(ContextGuard.decision(inputTokens: 10, contextSize: 0) == .reject)
        #expect(ContextGuard.decision(inputTokens: -1, contextSize: 4096) == .reject)
    }

    @Test func fitSendsTextThatIsWithinBudgetUnchanged() {
        let text = "2 onions, a bag of rice"
        #expect(ContextGuard.fit(text, textTokens: 10, overheadTokens: 500, contextSize: 4096, allowsTruncation: false) == text)
    }

    @Test func fitCutsTruncatableTextAtASentenceBoundary() {
        let text = "Two onions. A bag of rice. Three carrots and a leek."
        // Budget 14, overhead 2: 12 of 16 text tokens may stay, so at most 39 of 52 characters.
        let fitted = ContextGuard.fit(text, textTokens: 16, overheadTokens: 2, contextSize: 20, allowsTruncation: true)
        #expect(fitted == "Two onions. A bag of rice.")
    }

    @Test func fitRejectsOverBudgetTextThatMayNotBeCut() {
        let fitted = ContextGuard.fit("A long recipe.", textTokens: 16, overheadTokens: 2, contextSize: 20, allowsTruncation: false)
        #expect(fitted == nil)
    }

    @Test func fitRejectsWhenInstructionsAndSchemaAloneUseTheBudget() {
        #expect(ContextGuard.fit("rice", textTokens: 2, overheadTokens: 14, contextSize: 20, allowsTruncation: true) == nil)
    }

    @Test func fitRejectsTextLargerThanTheWholeWindowEvenWhenTruncatable() {
        #expect(ContextGuard.fit("rice", textTokens: 20, overheadTokens: 1, contextSize: 10, allowsTruncation: true) == nil)
    }

    @Test func estimateIsAboutThreeCharactersPerTokenRoundedUp() {
        #expect(ContextGuard.estimatedTokens(for: "") == 0)
        #expect(ContextGuard.estimatedTokens(for: "abc") == 1)
        #expect(ContextGuard.estimatedTokens(for: "abcd") == 2)
    }
}

struct TextTruncatorTests {
    @Test func shortTextIsKept() {
        #expect(TextTruncator.truncate("rice", maxCharacters: 10) == "rice")
        #expect(TextTruncator.truncate("rice", maxCharacters: 4) == "rice")
    }

    @Test func nonPositiveLimitsGiveEmptyText() {
        #expect(TextTruncator.truncate("rice", maxCharacters: 0) == "")
        #expect(TextTruncator.truncate("rice", maxCharacters: -3) == "")
    }

    @Test func listsWithoutSentencesAreCutAfterTheLastWholeEntry() {
        #expect(TextTruncator.truncate("2 onions, a bag of rice, 3 carrots", maxCharacters: 28) == "2 onions, a bag of rice")
        #expect(TextTruncator.truncate("milk\neggs\nbutter", maxCharacters: 12) == "milk\neggs")
    }

    @Test func singleEntriesAreCutAtAWordThenHardCut() {
        #expect(TextTruncator.truncate("smoked streaky bacon", maxCharacters: 16) == "smoked streaky")
        #expect(TextTruncator.truncate("cauliflower", maxCharacters: 4) == "caul")
    }
}
