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

/// The onboarding answers and the step the user is on. Nothing is asked twice; everything is editable in Settings.
@Observable @MainActor
public final class OnboardingModel {
    /// The screens, in order. Each asks one question.
    public enum Step: Int, CaseIterable, Sendable {
        case welcome, leaveOut, eatBy, goal, household, equipment, easierToUse
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

    /// Consent to send derived settings and recipe text to the cloud assistant; off by default.
    public var aiConsent = false
    public var allergens: Set<Allergen> = []
    /// Free-text intolerances, separated by commas.
    public var intoleranceText = ""
    public var eatBy: Set<EatByChoice> = []
    public private(set) var medicalFlags: Set<MedicalFlag> = []
    public private(set) var medicalPreferNotToSay = false
    /// `nil` until chosen; a skipped goal saves as `.maintain`.
    public var goal: Goal?
    /// Saved within `householdRange`.
    public var householdSize = ProfileDefaults.householdSize
    public var maxCookMinutes = ProfileDefaults.maxCookMinutes
    /// `nil` means "Prefer not to say".
    public var birthYear: Int?
    public var equipment: Set<Equipment> = ProfileDefaults.equipment
    public var prefersSimpleLayout = false
    public var timersFlashAndVibrate = true
    /// Off by default: calories and amounts stay hidden.
    public var showsNumbers = false

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

    /// The step's position, such as "2 of 7".
    public var progressText: String {
        AccountCopy.progress(step: step.rawValue + 1, of: Step.allCases.count)
    }

    /// The step's position for VoiceOver.
    public var spokenProgress: String {
        AccountCopy.spokenProgress(step: step.rawValue + 1, of: Step.allCases.count)
    }

    public var canGoBack: Bool { step != .welcome }
    public var isLastStep: Bool { step == Step.allCases.last }
    /// Every question after the welcome screen can be skipped.
    public var canSkip: Bool { step != .welcome }

    /// Years offered for the year of birth, newest first.
    public var birthYearChoices: [Int] {
        ProfileDefaults.birthYears(referenceYear: ProfileDefaults.referenceYear(at: dates.now))
    }

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

    /// Clears this step's answers back to their defaults and moves on; on the last step it finishes.
    public func skip() async {
        guard canSkip else { return }
        resetAnswers(for: step)
        if isLastStep {
            await finish()
        } else {
            next()
        }
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
        preferences.prefersSimpleLayout = prefersSimpleLayout
        preferences.timersFlashAndVibrate = timersFlashAndVibrate
        preferences.birthYearDeclined = birthYear == nil
        error = nil
        isFinished = true
    }

    /// The profile the answers describe. Sex, height and weight are never asked.
    func makeProfile(referenceYear: Int) -> UserProfile {
        UserProfile(
            birthYear: ProfileDefaults.birthYear(birthYear, referenceYear: referenceYear),
            sex: .unspecified,
            heightCm: ProfileDefaults.heightCm,
            weightKg: nil,
            activityLevel: ProfileDefaults.activityLevel,
            goal: goal ?? ProfileDefaults.goal,
            householdSize: householdSize.clamped(to: Self.householdRange),
            currencyCode: currencyCode,
            maxCookMinutes: ProfileDefaults.cookMinutes(nearest: maxCookMinutes),
            equipment: equipment,
            showsNumbers: showsNumbers,
            consents: Consents(aiProcessing: aiConsent)
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

    private func resetAnswers(for step: Step) {
        switch step {
        case .welcome:
            aiConsent = false
        case .leaveOut:
            allergens = []
            intoleranceText = ""
        case .eatBy:
            eatBy = []
            medicalFlags = []
            medicalPreferNotToSay = false
        case .goal:
            goal = nil
        case .household:
            householdSize = ProfileDefaults.householdSize
            maxCookMinutes = ProfileDefaults.maxCookMinutes
            birthYear = nil
        case .equipment:
            equipment = ProfileDefaults.equipment
        case .easierToUse:
            prefersSimpleLayout = false
            timersFlashAndVibrate = true
            showsNumbers = false
        }
    }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
