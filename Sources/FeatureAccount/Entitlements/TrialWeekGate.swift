import Foundation

/// A small persistent store of flags; `UserDefaultsKeyValueStore` in the app, in memory in tests.
public nonisolated protocol KeyValueStore: Sendable {
    /// The flag stored under `key`, or `nil` if none was ever stored.
    func bool(forKey key: String) -> Bool?
    /// Stores `value` under `key`.
    func set(_ value: Bool, forKey key: String)
}

/// `KeyValueStore` backed by `UserDefaults`.
public nonisolated struct UserDefaultsKeyValueStore: KeyValueStore {
    /// `UserDefaults` is documented as thread-safe but not marked `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults

    /// Creates a store over `defaults`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func bool(forKey key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    public func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

/// The keys FeatureAccount stores flags under.
nonisolated enum AccountKey {
    static let freeWeekUsed = "larder.freeWeekUsed"
    static let prefersSimpleLayout = "larder.prefersSimpleLayout"
    static let timersFlashAndVibrate = "larder.timersFlashAndVibrate"
    static let birthYearDeclined = "larder.birthYearDeclined"
}

/// The one generated week a free user gets ("Planning one week is free").
public nonisolated struct TrialWeekGate: Sendable {
    private let store: any KeyValueStore

    /// Creates a gate over `store`.
    public init(store: any KeyValueStore) {
        self.store = store
    }

    /// Whether the free generated week is still unused.
    public var canGenerateFreeWeek: Bool {
        store.bool(forKey: AccountKey.freeWeekUsed) != true
    }

    /// Records that the free week has been generated.
    public func markFreeWeekUsed() {
        store.set(true, forKey: AccountKey.freeWeekUsed)
    }
}

/// Comfort settings from "Make Larder easier to use".
public nonisolated struct ComfortPreferences: Sendable {
    private let store: any KeyValueStore

    /// Creates preferences over `store`.
    public init(store: any KeyValueStore) {
        self.store = store
    }

    /// Fewer choices per screen and plainer layouts; off by default.
    public var prefersSimpleLayout: Bool {
        get { store.bool(forKey: AccountKey.prefersSimpleLayout) ?? false }
        nonmutating set { store.set(newValue, forKey: AccountKey.prefersSimpleLayout) }
    }

    /// Cooking timers flash the screen and vibrate as well as sound; on by default.
    public var timersFlashAndVibrate: Bool {
        get { store.bool(forKey: AccountKey.timersFlashAndVibrate) ?? true }
        nonmutating set { store.set(newValue, forKey: AccountKey.timersFlashAndVibrate) }
    }

    /// Whether the user chose "Prefer not to say" for their year of birth.
    var birthYearDeclined: Bool {
        get { store.bool(forKey: AccountKey.birthYearDeclined) ?? false }
        nonmutating set { store.set(newValue, forKey: AccountKey.birthYearDeclined) }
    }
}
