import Foundation
import LarderCore
import Observation

/// Why onboarding could not finish.
public nonisolated enum OnboardingError: Error, Hashable, Sendable {
    case saveFailed
}

/// One choice on the "Anything we eat by?" screen.
public nonisolated enum EatByChoice: Hashable, Sendable {
    case diet(DietPattern)
    case religious(ReligiousRule)

    /// Diets first, then religious rules.
    public static let all: [EatByChoice] = DietPattern.allCases.map(diet) + ReligiousRule.allCases.map(religious)
}

/// The onboarding answers and the step the user is on: a welcome screen, then three short questions.
/// Every question is optional, nothing is ever cleared by moving on, and everything else lives in Settings.
@Observable @MainActor
public final class OnboardingModel {
    /// The screens, in order. The welcome screen asks nothing; each later screen asks one question.
    public enum Step: Int, CaseIterable, Sendable {
        case welcome, leaveOut, eatBy, household
    }

    /// Allergens, most commonly avoided first.
    public nonisolated static let allergenChoices: [Allergen] = [
        .peanut, .treeNut, .milk, .egg, .wheat, .gluten, .soy, .sesame,
        .fish, .crustacean, .mollusc, .celery, .mustard, .lupin, .sulphites,
    ]
    /// Conditions offered at setup; an eating-disorder history is never asked about.
    public nonisolated static let medicalChoices: [MedicalFlag] = [
        .coeliacDisease, .hypertension, .type1Diabetes, .type2Diabetes, .chronicKidneyDisease, .pregnancy,
    ]
    /// Cook-time choices in minutes.
    public nonisolated static let cookMinuteChoices = ProfileDefaults.cookMinuteChoices
    /// Allowed household sizes.
    public nonisolated static let householdRange = ProfileDefaults.householdRange

    public private(set) var step: Step = .welcome
    public private(set) var isSaving = false
    public private(set) var isFinished = false
    public private(set) var error: OnboardingError?

    public var allergens: Set<Allergen> = []
    /// Free-text intolerances, separated by commas.
    public var intoleranceText = ""
    public var eatBy: Set<EatByChoice> = []
    public private(set) var medicalFlags: Set<MedicalFlag> = []
    public private(set) var medicalPreferNotToSay = false
    /// Saved within `householdRange`.
    public var householdSize = ProfileDefaults.householdSize
    public var maxCookMinutes = ProfileDefaults.maxCookMinutes

    private let profiles: any ProfileRepository
    private let preferences: ComfortPreferences
    private let dates: any DateProvider
    private let currencyCode: String

    /// Creates onboarding that saves into `profiles` and `preferences`; `locale` supplies the budget currency.
    public init(
        profiles: any ProfileRepository,
        preferences: ComfortPreferences,
        dates: any DateProvider,
        locale: Locale = .current
    ) {
        self.profiles = profiles
        self.preferences = preferences
        self.dates = dates
        self.currencyCode = locale.currency?.identifier ?? "USD"
    }

    /// How many questions follow the welcome screen.
    public static var questionCount: Int { Step.allCases.count - 1 }

    /// The question's position, such as "Question 2 of 3"; empty on the welcome screen.
    public var progressText: String {
        guard step != .welcome else { return "" }
        return AccountCopy.progress(step: step.rawValue, of: Self.questionCount)
    }

    /// How far through the questions the user is, from 0 to 1.
    public var progress: Double {
        Double(step.rawValue) / Double(Self.questionCount)
    }

    public var canGoBack: Bool { step != .welcome }
    public var isLastStep: Bool { step == Step.allCases.last }
    /// Every question can be left for later; the welcome screen only moves on.
    public var canSetUpLater: Bool { step != .welcome }

    /// Moves to the next step; does nothing on the last one, which finishes instead.
    public func next() {
        guard let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    /// Moves to the previous step, keeping every answer.
    public func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Saves every answer given so far and finishes; unanswered questions keep their defaults.
    public func setUpLater() async {
        guard canSetUpLater else { return }
        await finish()
    }

    /// Selects or clears a condition; choosing one withdraws "Prefer not to say".
    public func toggleMedical(_ flag: MedicalFlag) {
        if medicalFlags.contains(flag) {
            medicalFlags.remove(flag)
        } else {
            medicalFlags.insert(flag)
            medicalPreferNotToSay = false
        }
    }

    /// Clears every condition and records "Prefer not to say".
    public func preferNotToSayMedical() {
        medicalFlags = []
        medicalPreferNotToSay = true
    }

    /// Saves constraints, default targets, then the profile, so a failed save leaves onboarding unfinished.
    public func finish() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let now = dates.now
        let referenceYear = ProfileDefaults.referenceYear(at: now)
        let profile = makeProfile(referenceYear: referenceYear)
        let constraints = makeConstraints(at: now)
        let targets = NutrientTargets.defaults(for: profile, constraints: constraints, referenceYear: referenceYear)
        do {
            try await profiles.saveConstraints(constraints)
            try await profiles.saveTargets(targets)
            try await profiles.save(profile)
        } catch {
            self.error = .saveFailed
            return
        }
        // Birth year is not asked at setup; Settings offers it, and until then nutrient ranges use the default age.
        preferences.birthYearDeclined = true
        error = nil
        isFinished = true
    }

    /// The profile the answers describe. Sex, height, weight, goal and birth year are never asked at setup.
    func makeProfile(referenceYear: Int) -> UserProfile {
        UserProfile(
            birthYear: ProfileDefaults.birthYear(nil, referenceYear: referenceYear),
            sex: .unspecified,
            heightCm: ProfileDefaults.heightCm,
            weightKg: nil,
            activityLevel: ProfileDefaults.activityLevel,
            goal: ProfileDefaults.goal,
            householdSize: householdSize.clamped(to: Self.householdRange),
            currencyCode: currencyCode,
            maxCookMinutes: ProfileDefaults.cookMinutes(nearest: maxCookMinutes),
            equipment: ProfileDefaults.equipment,
            showsNumbers: false,
            consents: Consents(aiProcessing: false)
        )
    }

    /// The constraints the answers describe, each hard and on its kind's axis.
    func makeConstraints(at date: Date) -> [DietaryConstraint] {
        let allergenKinds = Self.allergenChoices.filter(allergens.contains).map(ConstraintKind.allergen)
        let intoleranceKinds = Self.intolerances(in: intoleranceText).map(ConstraintKind.intolerance)
        let eatByKinds = EatByChoice.all.filter(eatBy.contains).map { choice -> ConstraintKind in
            switch choice {
            case .diet(let diet): .diet(diet)
            case .religious(let rule): .religious(rule)
            }
        }
        let medicalKinds = Self.medicalChoices.filter(medicalFlags.contains).map(ConstraintKind.medical)
        return (allergenKinds + intoleranceKinds + eatByKinds + medicalKinds).map { DietaryConstraint.userSet($0, at: date) }
    }

    /// Comma- or line-separated entries, trimmed, without blanks or case-insensitive repeats.
    static func intolerances(in text: String) -> [String] {
        var seen: Set<String> = []
        return text
            .split { $0 == "," || $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
