import Foundation
import LarderCore
import Testing
@testable import FeatureAccount

@MainActor
@Suite("SettingsModel")
struct SettingsModelTests {
    private let flags = InMemoryKeyValueStore()
    private let deletions = CallCounter()

    private func loaded(
        profile: UserProfile? = sampleProfile,
        constraints: [DietaryConstraint] = [],
        targets: [NutrientTarget] = [],
        deleteFails: Bool = false
    ) async -> (SettingsModel, FakeProfileRepository) {
        let repository = FakeProfileRepository(profile: profile, constraints: constraints, targets: targets)
        let library = FakeLibrary()
        let deletions = deletions
        let model = SettingsModel(
            profiles: repository,
            exporter: ExportBuilder(profiles: repository, recipes: library, pantry: library, plans: library),
            preferences: ComfortPreferences(store: flags),
            dates: FixedDates(),
            deleteAllData: {
                deletions.increment()
                if deleteFails { throw FakeError.failed }
            }
        )
        await model.load()
        return (model, repository)
    }

    @Test func loadReadsProfileAndConstraints() async {
        let peanut = DietaryConstraint.userSet(.allergen(.peanut), at: referenceNow)
        let (model, _) = await loaded(constraints: [peanut])
        #expect(model.profile == sampleProfile)
        #expect(model.constraints == [peanut])
        #expect(model.error == nil)
    }

    @Test func loadFailureSetsError() async {
        let repository = FakeProfileRepository(profile: sampleProfile)
        await repository.setFailsReads(true)
        let library = FakeLibrary()
        let model = SettingsModel(
            profiles: repository,
            exporter: ExportBuilder(profiles: repository, recipes: library, pantry: library, plans: library),
            preferences: ComfortPreferences(store: flags), dates: FixedDates(), deleteAllData: {}
        )
        await model.load()
        #expect(model.error == .loadFailed)
        #expect(model.profile == nil)
    }

    @Test func showNumbersPersists() async {
        let (model, repository) = await loaded()
        await model.setShowsNumbers(true)
        #expect(await repository.storedProfile?.showsNumbers == true)
        #expect(model.profile?.showsNumbers == true)
    }

    @Test func aiConsentPersistsBothWays() async {
        let (model, repository) = await loaded()
        await model.setAIConsent(true)
        #expect(await repository.storedProfile?.consents.aiProcessing == true)
        await model.setAIConsent(false)
        #expect(await repository.storedProfile?.consents.aiProcessing == false)
    }

    @Test func comfortTogglesPersist() async {
        let (model, _) = await loaded()
        model.setTimersFlashAndVibrate(false)
        let reread = ComfortPreferences(store: flags)
        #expect(reread.timersFlashAndVibrate == false)
        #expect(model.timersFlashAndVibrate == false)
    }

    @Test func householdAndCookTimeAreKeptInRange() async {
        let (model, repository) = await loaded()
        await model.setHouseholdSize(0)
        await model.setMaxCookMinutes(17)
        let stored = await repository.storedProfile
        #expect(stored?.householdSize == 1)
        #expect(stored?.maxCookMinutes == 15)
    }

    @Test func equipmentTogglesOnAndOff() async {
        let (model, repository) = await loaded()
        await model.setEquipment(.slowCooker, included: true)
        await model.setEquipment(.oven, included: false)
        #expect(await repository.storedProfile?.equipment == [.stovetop, .slowCooker])
    }

    @Test func preferNotToSayBirthYearUsesTheReferenceAge() async {
        let (model, repository) = await loaded()
        await model.setBirthYear(nil)
        #expect(await repository.storedProfile?.birthYear == 1991)
        #expect(model.displayedBirthYear == nil)
        await model.setBirthYear(1979)
        #expect(model.displayedBirthYear == 1979)
        #expect(ComfortPreferences(store: flags).birthYearDeclined == false)
    }

    @Test func saveFailureKeepsTheOldProfile() async {
        let (model, repository) = await loaded()
        await repository.setFailsSaves(true)
        await model.setShowsNumbers(true)
        #expect(model.error == .saveFailed)
        #expect(model.profile?.showsNumbers == false)
    }

    @Test func goalChangeRefreshesTargetsAndKeepsCustomOnes() async throws {
        let custom = NutrientTarget(nutrient: .fiber, basis: .perDay, target: 35, priority: 2, source: .custom)
        let (model, repository) = await loaded(targets: [custom])
        await model.setGoal(.eatBetter)
        let targets = await repository.storedTargets
        #expect(targets.contains(custom))
        #expect(targets.filter { $0.nutrient == .fiber }.count == 1)
        #expect(targets.contains { $0.nutrient == .sodium })
    }

    @Test func addingPregnancyDropsTheEnergyTarget() async {
        let (model, repository) = await loaded()
        await model.setGoal(.eatBetter)
        #expect(await repository.storedTargets.contains { $0.nutrient == .energy })
        await model.add(.medical(.pregnancy))
        #expect(await !repository.storedTargets.contains { $0.nutrient == .energy })
    }

    @Test func addedConstraintsLandOnTheirAxis() async {
        let (model, repository) = await loaded()
        await model.add(.allergen(.sesame))
        await model.add(.religious(.kosher))
        await model.add(.diet(.pescatarian))
        await model.add(.dislike(.name("  Olives ")))
        let stored = await repository.storedConstraints
        #expect(stored.map(\.axis) == [.medical, .religious, .ethical, .preference])
        #expect(stored.map(\.strictness) == [.hard, .hard, .hard, .soft])
        #expect(stored.last?.kind == .dislike(.name("Olives")))
        #expect(model.constraints(on: .medical).map(\.kind) == [.allergen(.sesame)])
    }

    @Test func blankAndRepeatedConstraintsAreIgnored() async {
        let (model, repository) = await loaded()
        await model.add(.allergen(.egg))
        await model.add(.allergen(.egg))
        await model.add(.intolerance("   "))
        #expect(await repository.storedConstraints.count == 1)
    }

    @Test func removingAMedicalAllergenNeedsConfirmation() async {
        let peanut = DietaryConstraint.userSet(.allergen(.peanut), at: referenceNow)
        let (model, repository) = await loaded(constraints: [peanut])
        await model.requestRemoval(peanut)
        #expect(model.pendingRemoval == peanut)
        #expect(await repository.storedConstraints == [peanut])
        await model.confirmRemoval()
        #expect(model.pendingRemoval == nil)
        #expect(await repository.storedConstraints.isEmpty)
    }

    @Test func cancellingRemovalKeepsTheAllergen() async {
        let peanut = DietaryConstraint.userSet(.allergen(.peanut), at: referenceNow)
        let (model, repository) = await loaded(constraints: [peanut])
        await model.requestRemoval(peanut)
        model.cancelRemoval()
        await model.confirmRemoval()
        #expect(model.pendingRemoval == nil)
        #expect(await repository.storedConstraints == [peanut])
    }

    @Test func removingAPreferenceIsImmediate() async {
        let dislike = DietaryConstraint.userSet(.dislike(.name("Olives")), at: referenceNow)
        let diet = DietaryConstraint.userSet(.diet(.vegan), at: referenceNow)
        let (model, repository) = await loaded(constraints: [dislike, diet])
        await model.requestRemoval(dislike)
        #expect(model.pendingRemoval == nil)
        #expect(await repository.storedConstraints == [diet])
    }

    @Test func deleteWithoutConfirmationDoesNothing() async {
        let (model, _) = await loaded()
        await model.deleteAllData()
        #expect(deletions.value == 0)
        #expect(model.profile != nil)
    }

    @Test func cancelledDeleteDoesNothing() async {
        let (model, _) = await loaded()
        model.requestDeleteAll()
        model.cancelDeleteAll()
        await model.deleteAllData()
        #expect(deletions.value == 0)
    }

    @Test func confirmedDeleteCallsTheEraserOnce() async {
        let (model, _) = await loaded(constraints: [.userSet(.allergen(.egg), at: referenceNow)])
        model.requestDeleteAll()
        #expect(model.isConfirmingDelete)
        await model.deleteAllData()
        await model.deleteAllData()
        #expect(deletions.value == 1)
        #expect(model.profile == nil)
        #expect(model.constraints.isEmpty)
        #expect(model.isConfirmingDelete == false)
    }

    @Test func failedDeleteKeepsStateAndReports() async {
        let (model, _) = await loaded(deleteFails: true)
        model.requestDeleteAll()
        await model.deleteAllData()
        #expect(model.error == .deleteFailed)
        #expect(model.profile == sampleProfile)
    }

    @Test func addableKindsNeverOfferEatingDisorderHistory() {
        #expect(!SettingsView.addableKinds(on: .medical).contains(.medical(.eatingDisorderHistory)))
        #expect(SettingsView.addableKinds(on: .ethical).count == DietPattern.allCases.count)
    }
}

@Suite("Paywall copy")
struct PaywallCopyTests {
    @Test func monthlyPriceReadsPlainly() {
        #expect(AccountCopy.Paywall.price(monthlyProduct) == "$7.99 a month")
    }

    @Test func annualPriceStatesTheTrialFirst() {
        #expect(AccountCopy.Paywall.price(annualProduct) == "7 days free, then $49.99 a year")
    }

    @Test func noCopySellsUrgency() {
        let all = AccountCopy.Paywall.features.map(\.text) + [AccountCopy.Paywall.staysFree, AccountCopy.Paywall.renews]
        for line in all {
            #expect(!line.lowercased().contains("limited time"))
            #expect(!line.contains("!"))
        }
    }
}
