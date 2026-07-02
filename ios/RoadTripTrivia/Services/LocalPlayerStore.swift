import Foundation

/// Everything this app remembers about the player, kept only in on-device
/// UserDefaults. No accounts, no server-side profile — age/name are only
/// ever sent to a Cloud Function as part of a specific game's roster, and
/// that game doc (age included) is deleted when the game ends. See
/// docs/api-contract.md for the no-persistent-PII rule this mirrors.
final class LocalPlayerStore {
    static let shared = LocalPlayerStore()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let displayName = "localPlayer.displayName"
        static let age = "localPlayer.age"
        static let lastGameCode = "localPlayer.lastGameCode"
    }

    private init() {}

    var displayName: String? {
        get { defaults.string(forKey: Key.displayName) }
        set { defaults.set(newValue, forKey: Key.displayName) }
    }

    var age: Int? {
        get {
            let value = defaults.integer(forKey: Key.age)
            return value == 0 ? nil : value
        }
        set { defaults.set(newValue, forKey: Key.age) }
    }

    var hasCompletedAgeGate: Bool { age != nil }

    /// Cached so the app can offer "resume your trip" after a rest stop
    /// without the player re-typing the code.
    var lastGameCode: String? {
        get { defaults.string(forKey: Key.lastGameCode) }
        set { defaults.set(newValue, forKey: Key.lastGameCode) }
    }

    func clearLastGameCode() {
        defaults.removeObject(forKey: Key.lastGameCode)
    }
}
