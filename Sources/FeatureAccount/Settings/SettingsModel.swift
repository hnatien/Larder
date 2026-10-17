import Foundation
import LarderCore
import Observation

/// Why a settings action failed.
public nonisolated enum SettingsError: Error, Hashable, Sendable {
    case loadFailed
    case saveFailed
    case deleteFailed
}

/// The settings screen's state. Every change saves at once; targets follow profile and constraint changes.
@Observable @MainActor
public final class SettingsModel {
    /// The axes shown under "What we leave out".
    public nonisolated static let editableAxes: [ConstraintAxis] = [.medical, .religious, .ethical, .preference]

    public private(set) var profile: UserProfile?
    public private(set) var constraints: [DietaryConstraint] = []
    public private(set) var isLoading = false
    public private(set) var error: SettingsError?
    /// A medical constraint waiting for the user to confirm its removal.
    public private(set) var pendingRemoval: DietaryConstraint?
    /// True while "Delete all data" waits for confirmation; deletion does nothing otherwise.
    public private(set) var isConfirmingDelete = false
    public private(set) var birthYearDeclined: Bool
    public private(set) var timersFlashAndVibrate: Bool
    /// The last rule taken off, while Undo can put it back.
    public private(set) var lastRemoved: DietaryConstraint?
    /// The "Export everything" file.
    public let exportDocument: ExportDocument

    private let profiles: any ProfileRepository
    private let preferences: ComfortPreferences
    private let dates: any DateProvider
    private let deleteEverything: @Sendable () async throws -> Void
    private let trialWeek: TrialWeekGate?

    /// Creates the model; `deleteAllData` erases every store and is called only after confirmation, and `trialWeek`
    /// says whether the free planned week is still there.
    public init(
        profiles: any ProfileRepository,
        exporter: ExportBuilder,
        preferences: ComfortPreferences,
        dates: any DateProvider,
        trialWeek: TrialWeekGate? = nil,
        deleteAllData: @escaping @Sendable () async throws -> Void
    ) {
        self.profiles = profiles
        self.trialWeek = trialWeek
        self.preferences = preferences
        self.dates = dates
        self.deleteEverything = deleteAllData
        self.exportDocument = ExportDocument(builder: exporter, dates: dates)
        self.birthYearDeclined = preferences.birthYearDeclined
        self.timersFlashAndVibrate = preferences.timersFlashAndVibrate
    }

    /// Whether a free user's one planned week is still unused; `nil` when Larder cannot tell.
    public var freeWeekAvailable: Bool? { trialWeek?.canGenerateFreeWeek }

    /// Years offered for the year of birth, newest first.
    public var birthYearChoices: [Int] { ProfileDefaults.birthYears(referenceYear: referenceYear) }

    /// The year to show: `nil` for "Prefer not to say".
    public var displayedBirthYear: Int? { birthYearDeclined ? nil : profile?.birthYear }

    /// Loads the profile and constraints.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await profiles.profile()
            constraints = try await profiles.constraints()
            error = nil
        } catch {
            self.error = .loadFailed
        }
    }

    public func setGoal(_ goal: Goal) async { await updateProfile { $0.goal = goal } }

    public func setHouseholdSize(_ size: Int) async {
        await updateProfile { $0.householdSize = size.clamped(to: ProfileDefaults.householdRange) }
    }

    public func setMaxCookMinutes(_ minutes: Int) async {
        await updateProfile { $0.maxCookMinutes = ProfileDefaults.cookMinutes(nearest: minutes) }
    }

    public func setEquipment(_ equipment: Equipment, included: Bool) async {
        await updateProfile { profile in
            if included { profile.equipment.insert(equipment) } else { profile.equipment.remove(equipment) }
        }
    }

    public func setShowsNumbers(_ shows: Bool) async { await updateProfile { $0.showsNumbers = shows } }

    public func setAIConsent(_ granted: Bool) async { await updateProfile { $0.consents.aiProcessing = granted } }

    /// Sets the year of birth; `nil` means "Prefer not to say".
    public func setBirthYear(_ year: Int?) async {
        let stored = ProfileDefaults.birthYear(year, referenceYear: referenceYear)
        let declined = stored != year
        guard await updateProfile({ $0.birthYear = stored }) else { return }
        preferences.birthYearDeclined = declined
        birthYearDeclined = declined
    }

    public func setTimersFlashAndVibrate(_ value: Bool) {
        preferences.timersFlashAndVibrate = value
        timersFlashAndVibrate = value
    }

    /// The constraints on `axis`, in saved order.
    public func constraints(on axis: ConstraintAxis) -> [DietaryConstraint] {
        constraints.filter { $0.axis == axis }
    }

    /// Whether a constraint of `kind` already exists.
    public func contains(_ kind: ConstraintKind) -> Bool {
        constraints.contains { $0.kind == kind }
    }

    /// Adds a user constraint on its kind's axis; blank text and repeats are ignored.
    public func add(_ kind: ConstraintKind) async {
        guard let kind = Self.normalised(kind), !contains(kind) else { return }
        await saveConstraints(constraints + [DietaryConstraint.userSet(kind, at: dates.now)])
    }

    /// Removes a constraint; a medical one waits in `pendingRemoval` for confirmation first.
    public func requestRemoval(_ constraint: DietaryConstraint) async {
        if constraint.axis == .medical {
            pendingRemoval = constraint
        } else {
            await remove(constraint.id)
        }
    }

    /// Removes the constraint waiting for confirmation.
    public func confirmRemoval() async {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        await remove(pending.id)
    }

    /// Keeps the constraint waiting for confirmation.
    public func cancelRemoval() {
        pendingRemoval = nil
    }

    /// Asks for confirmation before deleting everything.
    public func requestDeleteAll() {
        isConfirmingDelete = true
    }

    public func cancelDeleteAll() {
        isConfirmingDelete = false
    }

    /// Deletes all data once confirmed; without confirmation it does nothing.
    public func deleteAllData() async {
        guard isConfirmingDelete else { return }
        isConfirmingDelete = false
        do {
            try await deleteEverything()
        } catch {
            self.error = .deleteFailed
            return
        }
        profile = nil
        constraints = []
        error = nil
    }

    private var referenceYear: Int { ProfileDefaults.referenceYear(at: dates.now) }

    private func remove(_ id: DietaryConstraintID) async {
        let removed = constraints.first { $0.id == id }
        await saveConstraints(constraints.filter { $0.id != id })
        if error == nil { lastRemoved = removed }
    }

    /// Puts the last removed rule back where it was.
    public func undoRemoval() async {
        guard let removed = lastRemoved else { return }
        lastRemoved = nil
        guard !constraints.contains(where: { $0.id == removed.id }) else { return }
        await saveConstraints(constraints + [removed])
    }

    /// Lets the last removal stand.
    public func dismissRemovalUndo() {
        lastRemoved = nil
    }

    @discardableResult
    private func updateProfile(_ change: (inout UserProfile) -> Void) async -> Bool {
        guard var updated = profile else { return false }
        change(&updated)
        guard updated != profile else { return true }
        do {
            try await profiles.save(updated)
            profile = updated
            try await refreshTargets()
            error = nil
            return true
        } catch {
            self.error = .saveFailed
            return false
        }
    }

    private func saveConstraints(_ updated: [DietaryConstraint]) async {
        do {
            try await profiles.saveConstraints(updated)
            constraints = updated
            try await refreshTargets()
            error = nil
        } catch {
            self.error = .saveFailed
        }
    }

    private func refreshTargets() async throws {
        guard let profile else { return }
        let existing = try await profiles.targets()
        try await profiles.saveTargets(
            NutrientTargets.refreshed(existing, for: profile, constraints: constraints, referenceYear: referenceYear)
        )
    }

    private static func normalised(_ kind: ConstraintKind) -> ConstraintKind? {
        switch kind {
        case .intolerance(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .intolerance(trimmed)
        case .dislike(.name(let text)):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .dislike(.name(trimmed))
        default:
            return kind
        }
    }
}
