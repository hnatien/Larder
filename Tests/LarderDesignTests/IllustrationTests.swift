import Testing
@testable import LarderDesign

@MainActor
@Suite("Illustrations")
struct IllustrationTests {
    @Test(arguments: LarderIllustration.allCases)
    func everyIllustrationIsInTheCatalogue(illustration: LarderIllustration) {
        #expect(illustration.isAvailable, "\(illustration.rawValue) is missing from Illustrations.xcassets")
    }
}
