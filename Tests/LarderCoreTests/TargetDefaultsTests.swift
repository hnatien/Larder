import Foundation
import Testing
@testable import LarderCore

struct TargetDefaultsTests {
    private func target(_ nutrient: Nutrient, in targets: [NutrientTarget]) -> NutrientTarget? {
        targets.first { $0.nutrient == nutrient }
    }

    @Test func adultWithWeightUsesMifflinStJeorAndWeightBasedProtein() throws {
        let profile = Kitchen.profile(birthYear: 1986, sex: .male, heightCm: 180, weightKg: 80, activity: .moderate)

        let targets = NutrientTargets.defaults(for: profile, constraints: [], referenceYear: 2026)

        // 10 * 80 + 6.25 * 180 - 5 * 40 + 5 = 800 + 1125 - 200 + 5 = 1730 kcal; * 1.55 = 2681.5 kcal
        let energy = try #require(target(.energy, in: targets))
        #expect(Kitchen.isClose(energy.target, 2681.5))
        #expect(Kitchen.isClose(energy.min, 2681.5 * 0.9))
        #expect(Kitchen.isClose(energy.max, 2681.5 * 1.1))
        #expect(energy.basis == .perDay)
        // protein 0.8 / 1.2 / 1.6 g/kg * 80 kg = 64 / 96 / 128 g
        let protein = try #require(target(.protein, in: targets))
        #expect(Kitchen.isClose(protein.min, 64))
        #expect(Kitchen.isClose(protein.target, 96))
        #expect(Kitchen.isClose(protein.max, 128))
        #expect(target(.sodium, in: targets)?.max == 2300)
        #expect(target(.sodium, in: targets)?.source == .dga2025)
        #expect(target(.potassium, in: targets)?.target == 3400)
    }

    // base 10 * 60 + 6.25 * 165 - 5 * 30 = 600 + 1031.25 - 150 = 1481.25; sedentary factor 1.2
    static let sexCases: [(Sex, Double, Double)] = [
        (.female, (1481.25 - 161) * 1.2, 2600),
        (.male, (1481.25 + 5) * 1.2, 3400),
        (.unspecified, (1481.25 - 78) * 1.2, 3000),
    ]

    @Test(arguments: sexCases)
    func energyAndPotassiumBySex(sex: Sex, expectedKcal: Double, expectedPotassium: Double) {
        let profile = Kitchen.profile(birthYear: 1996, sex: sex, heightCm: 165, weightKg: 60, activity: .sedentary)

        let targets = NutrientTargets.defaults(for: profile, constraints: [], referenceYear: 2026)

        #expect(Kitchen.isClose(target(.energy, in: targets)?.target, expectedKcal))
        #expect(target(.potassium, in: targets)?.target == expectedPotassium)
    }

    @Test(arguments: [
        (ActivityLevel.sedentary, 1.2), (.light, 1.375), (.moderate, 1.55), (.active, 1.725), (.veryActive, 1.9),
    ])
    func activityFactorMultipliesRestingEnergy(level: ActivityLevel, factor: Double) {
        let profile = Kitchen.profile(birthYear: 1986, sex: .male, heightCm: 180, weightKg: 80, activity: level)

        let targets = NutrientTargets.defaults(for: profile, constraints: [], referenceYear: 2026)

        #expect(Kitchen.isClose(target(.energy, in: targets)?.target, 1730 * factor))
    }

    @Test func adultWithoutWeightUsesReferenceValues() {
        let targets = NutrientTargets.defaults(for: Kitchen.profile(weightKg: nil), constraints: [], referenceYear: 2026)

        #expect(target(.energy, in: targets)?.target == 2000)
        #expect(target(.protein, in: targets)?.min == 50)
        #expect(target(.protein, in: targets)?.target == 75)
        #expect(target(.protein, in: targets)?.max == 100)
    }

    @Test(arguments: [0.0, -5, .nan, .infinity])
    func invalidWeightIsTreatedAsMissing(weight: Double) {
        let targets = NutrientTargets.defaults(for: Kitchen.profile(weightKg: weight), constraints: [], referenceYear: 2026)

        #expect(target(.energy, in: targets)?.target == 2000)
        #expect(target(.protein, in: targets)?.target == 75)
    }

    @Test func twelveYearOldGetsCappedProteinAndChildSodium() throws {
        let profile = Kitchen.profile(birthYear: 2014, weightKg: 40)

        let targets = NutrientTargets.defaults(for: profile, constraints: [], referenceYear: 2026)

        // capped: target 0.8 * 40 = 32 g, ceiling 1.0 * 40 = 40 g
        let protein = try #require(target(.protein, in: targets))
        #expect(Kitchen.isClose(protein.target, 32))
        #expect(Kitchen.isClose(protein.max, 40))
        #expect(target(.sodium, in: targets)?.max == 1800)
    }

    @Test(arguments: [(2024, 1200.0), (2023, 1200), (2022, 1500), (2018, 1500), (2017, 1800), (2013, 1800), (2012, 2300)])
    func sodiumLimitByAge(birthYear: Int, expectedMax: Double) {
        let targets = NutrientTargets.defaults(for: Kitchen.profile(birthYear: birthYear), constraints: [], referenceYear: 2026)

        #expect(target(.sodium, in: targets)?.max == expectedMax)
    }

    @Test func kidneyDiseaseCapsProteinForAdults() throws {
        let profile = Kitchen.profile(weightKg: 70, goal: .moreProtein)

        let targets = NutrientTargets.defaults(
            for: profile, constraints: [Kitchen.constraint(.medical(.chronicKidneyDisease))], referenceYear: 2026
        )

        let protein = try #require(target(.protein, in: targets))
        #expect(Kitchen.isClose(protein.min, 56))
        #expect(Kitchen.isClose(protein.target, 56))
        #expect(Kitchen.isClose(protein.max, 70))
    }

    @Test(arguments: Goal.allCases)
    func hypertensionUsesWHOSodiumForEveryGoal(goal: Goal) throws {
        let targets = NutrientTargets.defaults(
            for: Kitchen.profile(goal: goal), constraints: [Kitchen.constraint(.medical(.hypertension))], referenceYear: 2026
        )

        let sodium = try #require(target(.sodium, in: targets))
        #expect(sodium.max == 2000)
        #expect(sodium.source == .who)
    }

    @Test func hypertensionKeepsAChildsLowerDGASodium() {
        let targets = NutrientTargets.defaults(
            for: Kitchen.profile(birthYear: 2017), constraints: [Kitchen.constraint(.medical(.hypertension))], referenceYear: 2026
        )

        #expect(target(.sodium, in: targets)?.max == 1800)
        #expect(target(.sodium, in: targets)?.source == .dga2025)
    }

    @Test func withoutHypertensionEatBetterKeepsDGASodium() {
        let targets = NutrientTargets.defaults(for: Kitchen.profile(goal: .eatBetter), constraints: [], referenceYear: 2026)

        #expect(target(.sodium, in: targets)?.max == 2300)
        #expect(target(.sodium, in: targets)?.source == .dga2025)
    }

    @Test(arguments: [MedicalFlag.eatingDisorderHistory, .pregnancy])
    func sensitiveConditionsOmitEnergyTarget(flag: MedicalFlag) {
        let targets = NutrientTargets.defaults(
            for: Kitchen.profile(weightKg: 70), constraints: [Kitchen.constraint(.medical(flag))], referenceYear: 2026
        )

        #expect(target(.energy, in: targets) == nil)
        #expect(!targets.contains { $0.nutrient == .energy && $0.max != nil })
        #expect(target(.protein, in: targets) != nil)
        #expect(target(.sodium, in: targets) != nil)
    }

    @Test func fatSugarAndFibreTargetsCarryBasisAndSource() throws {
        let targets = NutrientTargets.defaults(for: Kitchen.profile(), constraints: [], referenceYear: 2026)

        let fibre = try #require(target(.fiber, in: targets))
        #expect(fibre.basis == .per1000kcal)
        #expect(fibre.target == 14)
        let saturated = try #require(target(.saturatedFat, in: targets))
        #expect(saturated.basis == .percentEnergy)
        #expect(saturated.max == 10)
        #expect(saturated.source == .dga2025)
        let sugar = try #require(target(.addedSugar, in: targets))
        #expect(sugar.basis == .percentEnergy)
        #expect(sugar.max == 10)
        #expect(Set(targets.map(\.nutrient)) == [.energy, .protein, .fiber, .sodium, .saturatedFat, .addedSugar, .potassium])
    }
}
