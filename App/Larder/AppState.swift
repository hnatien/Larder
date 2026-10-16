import Observation

/// The app's tabs, in tab bar order.
enum AppTab: Hashable {
    case tonight, ledger, shelves, recipes, grocery
}

/// App-wide state the root view observes.
@Observable
final class AppState {
    /// Whether a profile is stored; `nil` until launch has read the store.
    var hasProfile: Bool?
    /// True when the store could not be opened or read at launch.
    var startupFailed = false
    var selectedTab = AppTab.tonight
}
