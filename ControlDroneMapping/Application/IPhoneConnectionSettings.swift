import Foundation

enum IPhoneConnectionSettings {
    static let enabledKey = "iphoneConnectionEnabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }
}
