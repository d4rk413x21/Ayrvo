import Foundation

enum AppIdentity {
    // Preserve macOS permissions, preferences, and Keychain access across the Ayrvo rename.
    static let bundleIdentifier = "io.github.d4rk413x21.Nutola"
    static let repositoryURL = URL(string: "https://github.com/d4rk413x21/Ayrvo")!

    /// Read the old preferences once; credentials remain in their separate Keychain service.
    static func importPreviousPreferences(
        defaults: UserDefaults = .standard,
        from previousDomain: String = "io.github.matheusgois-dd.Nutola",
        to currentDomain: String = bundleIdentifier
    ) {
        let marker = "didImportPreviousAppPreferences"
        var current = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard current[marker] as? Bool != true else { return }
        let previous = defaults.persistentDomain(forName: previousDomain) ?? [:]
        current.merge(previous) { existing, _ in existing }
        current[marker] = true
        defaults.setPersistentDomain(current, forName: currentDomain)
    }
}
