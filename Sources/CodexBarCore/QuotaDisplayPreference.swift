import Foundation

public enum QuotaDisplayPreference {
    public static let key = "usageBarsShowUsed"

    public static let personalDefault = true

    public static func showUsed(in defaults: UserDefaults, defaultValue: Bool = personalDefault) -> Bool {
        defaults.object(forKey: self.key) as? Bool ?? defaultValue
    }
}
