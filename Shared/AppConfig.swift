import Foundation

/// Server URL + device token, shared with the Share extension via the App Group.
enum AppConfig {
    static let appGroup = "group.cz.frca.jendapp"

    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static var serverURL: URL? {
        get { defaults.string(forKey: "serverURL").flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: "serverURL") }
    }

    static var token: String? {
        get { defaults.string(forKey: "token") }
        set { defaults.set(newValue, forKey: "token") }
    }

    static var client: APIClient? {
        guard let url = serverURL, let token, !token.isEmpty else { return nil }
        return APIClient(baseURL: url, token: token)
    }

    /// Handles jendapp://pair?url=…&token=… (printed by `jendapp pair`).
    static func applyPairingURL(_ url: URL) -> Bool {
        guard url.scheme == "jendapp", url.host() == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let server = items.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)),
              let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty
        else { return false }
        serverURL = server
        self.token = token
        return true
    }
}
