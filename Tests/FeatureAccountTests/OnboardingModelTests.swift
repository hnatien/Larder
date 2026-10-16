import Foundation
import LarderCore
import Testing
@testable import FeatureAccount

@MainActor
@Suite("OnboardingModel")
struct OnboardingModelTests {
    private let repository = FakeProfileRepository()
    private let flags = InMemoryKeyValueStore()

    private func makeModel() -> OnboardingModel {
        OnboardingModel(
            profiles: repository,
            preferences: ComfortPreferences(store: flags),
            dates: FixedDates(),
            locale: Locale(identifier: "en_GB")
        )
    }

    @Test func stepsRunInOrderWithProgress() {
        let model = makeModel()
        var seen: [OnboardingModel.Step] = []
        var progress: [String] = []
        for _ in OnboardingModel.Step.allCases {
            seen.append(model.step)
            progress.append(model.progressText)
            model.next()
        }
        #expect(seen == [.welcome, .leaveOut, .eatBy, .household])
        #expect(progress == ["", "Question 1 of 3", "Question 2 of 3", "Question 3 of 3"])
        #expect(model.step == .household)
        #expect(model.progress == 1)
        #expect(model.isLastStep)
    }

    @Test func backStopsAtWelcomeAndKeepsAnswers() {
        let model = makeModel()
        model.back()
        #expect(model.step == .welcome)
        #expect(model.canGoBack == false)
        model.next()
        model.allergens = [.sesame]
        model.next()
        model.back()
        #expect(model.step == .leaveOut)
        #expect(model.allergens == [.sesame])
    }

    @Test func welcomeCannotBeLeftForLater() async {
        let model = makeModel()
        #expect(model.canSetUpLater == false)
        await model.setUpLater()
        #expect(model.step == .welcome)
        #expect(model.isFinished == false)
        #expect(await repository.storedProfile == nil)
    }

    @Test func sensitiveSettingsAreOffAfterSetup() async throws {
        let model = makeModel()
        await model.finish()
        let profile = try #require(await repository.storedProfile)
        #expect(profile.consents.aiProcessing == false)
        #expect(profile.showsNumbers == false)
        #expect(ComfortPreferences(store: flags).timersFlashAndVibrate)
    }

    @Test func eatingDisorderHistoryIsNeverOffered() {
        #expect(!OnboardingModel.medicalChoices.contains(.eatingDisorderHistory))
        #expect(OnboardingModel.allergenChoices.count == Allergen.allCases.count)
        #expect(Set(OnboardingModel.allergenChoices) == Set(Allergen.allCases))
    }

    @Test func allergensAreHardMedicalUserConstraints() {
        let model = makeModel()
        model.allergens = [.sesame, .peanut]
        let constraints = model.makeConstraints(at: referenceNow)
        #expect(constraints.map(\.kind) == [.allergen(.peanut), .allergen(.sesame)])
        #expect(constraints.allSatisfy { $0.axis == .medical && $0.strictness == .hard && $0.source == .user })
        #expect(constraints.allSatisfy { $0.lastConfirmed == referenceNow })
    }

    @Test func intoleranceTextSplitsTrimsAndDropsRepeats() {
        let model = makeModel()
        model.intoleranceText = " lactose, ,FODMAPs\nLactose ,  "
        let constraints = model.makeConstraints(at: referenceNow)
        #expect(constraints.map(\.kind) == [.intolerance("lactose"), .intolerance("FODMAPs")])
        #expect(constraints.allSatisfy { $0.axis == .medical && $0.strictness == .hard })
    }

    @Test(arguments: EatByChoice.all)
    func eatByChoicesLandOnTheirAxis(choice: EatByChoice) throws {
        let model = makeModel()
        model.eatBy = [choice]
        let constraint = try #require(model.makeConstraints(at: referenceNow).first)
        switch choice {
        case .diet(let diet):
            #expect(constraint.kind == .diet(diet))
            #expect(constraint.axis == .ethical)
        case .religious(let rule):
            #expect(constraint.kind == .religious(rule))
            #expect(constraint.axis == .religious)
        }
        #expect(constraint.strictness == .hard)
    }

    @Test(arguments: OnboardingModel.medicalChoices)
    func medicalFlagsAreHardMedical(flag: MedicalFlag) throws {
        let model = makeModel()
        model.toggleMedical(flag)
        let constraint = try #require(model.makeConstraints(at: referenceNow).first)
        #expect(constraint.kind == .medical(flag))
        #expect(constraint.axis == .medical)
        #expect(constraint.strictness == .hard)
    }

    @Test func preferNotToSayClearsConditionsAndChoosingOneWithdrawsIt() {
        let model = makeModel()
        model.toggleMedical(.hypertension)
        model.preferNotToSayMedical()
        #expect(model.medicalFlags.isEmpty)
        #expect(model.medicalPreferNotToSay)
        model.toggleMedical(.pregnancy)
        #expect(model.medicalFlags == [.pregnancy])
        #expect(model.medicalPreferNotToSay == false)
        model.toggleMedical(.pregnancy)
        #expect(model.medicalFlags.isEmpty)
    }

    @Test func movingBetweenQuestionsNeverClearsAnswers() {
        let model = makeModel()
        model.next()
        model.allergens = [.milk]
        model.intoleranceText = "lactose"
        model.next()
        model.eatBy = [.diet(.vegan)]
        model.next()
        model.back()
        model.back()
        #expect(model.step == .leaveOut)
        #expect(model.allergens == [.milk])
        #expect(model.intoleranceText == "lactose")
        #expect(model.eatBy == [.diet(.vegan)])
    }

    @Test func setUpLaterKeepsEveryAnswerGivenSoFar() async {
        let model = makeModel()
        model.next()
        model.allergens = [.peanut]
        model.intoleranceText = "lactose"
        await model.setUpLater()
        #expect(model.isFinished)
        let kinds = await repository.storedConstraints.map(\.kind)
        #expect(kinds == [.allergen(.peanut), .intolerance("lactose")])
    }

    @Test func setUpLaterWithNothingAnsweredSavesSafeDefaults() async throws {
        let model = makeModel()
        model.next()
        await model.setUpLater()
        let profile = try #require(await repository.storedProfile)
        #expect(profile.birthYear == 2026 - 35)
        #expect(profile.sex == .unspecified)
        #expect(profile.heightCm == 170)
        #expect(profile.weightKg == nil)
        #expect(profile.goal == .maintain)
        #expect(profile.householdSize == 2)
        #expect(profile.maxCookMinutes == 35)
        #expect(profile.equipment == [.oven, .stovetop])
        #expect(profile.showsNumbers == false)
        #expect(profile.consents.aiProcessing == false)
        #expect(profile.currencyCode == "GBP")
        #expect(await repository.storedConstraints.isEmpty)
        #expect(ComfortPreferences(store: flags).birthYearDeclined)
    }

    @Test func finishSavesAnswers() async throws {
        let model = makeModel()
        model.householdSize = 4
        model.maxCookMinutes = 25
        await model.finish()
        #expect(model.isFinished)
        let profile = try #require(await repository.storedProfile)
        #expect(profile.householdSize == 4)
        #expect(profile.maxCookMinutes == 25)
        #expect(profile.consents.cloudSync == false)
    }

    @Test func outOfRangeAnswersAreClampedOrDeclined() async throws {
        let model = makeModel()
        model.householdSize = 12
        model.maxCookMinutes = 50
        await model.finish()
        let profile = try #require(await repository.storedProfile)
        #expect(profile.householdSize == 8)
        #expect(profile.maxCookMinutes == 45)
        #expect(profile.birthYear == 2026 - 35)
    }

    @Test func finishStoresDefaultTargetsForTheAnswers() async throws {
        let model = makeModel()
        model.toggleMedical(.chronicKidneyDisease)
        await model.finish()
        let profile = try #require(await repository.storedProfile)
        let constraints = await repository.storedConstraints
        let expected = NutrientTargets.defaults(for: profile, constraints: constraints, referenceYear: 2026)
        #expect(await repository.storedTargets == expected)
        #expect(!expected.isEmpty)
    }

    @Test func pregnancyLeavesNoEnergyTarget() async {
        let model = makeModel()
        model.toggleMedical(.pregnancy)
        await model.finish()
        let targets = await repository.storedTargets
        #expect(!targets.contains { $0.nutrient == .energy })
        #expect(targets.contains { $0.nutrient == .protein })
    }

    @Test func failedSaveLeavesOnboardingUnfinished() async {
        await repository.setFailsSaves(true)
        let model = makeModel()
        model.allergens = [.peanut]
        await model.finish()
        #expect(model.isFinished == false)
        #expect(model.error == .saveFailed)
        #expect(model.isSaving == false)
        #expect(await repository.storedProfile == nil)
        #expect(flags.bool(forKey: AccountKey.birthYearDeclined) == nil)
    }

    @Test func retryAfterFailureSucceeds() async {
        await repository.setFailsSaves(true)
        let model = makeModel()
        await model.finish()
        await repository.setFailsSaves(false)
        await model.finish()
        #expect(model.isFinished)
        #expect(model.error == nil)
    }
}
