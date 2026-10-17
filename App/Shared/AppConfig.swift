import Foundation

/// Public Eight Sleep mobile-client credentials and the hosts the unofficial
/// clients call. These are the app's OAuth client id and secret, not a user
/// password. They are the values published in lukas-clarke/pyEight `constants.py`.
enum AppConfig {
    static let appGroup = "group.com.chasemc67.eightsleepwatch.grok"
    static let keychainService = "com.chasemc67.eightsleepwatch.grok"

    static let clientID = "0894c7f33bb94800a03f1f4df13a4f38"
    static let clientSecret = "f0954a3ed5763ba3d06834c73731a32f15f168f47d4f164751275def86db0c76"

    static let authURL = URL(string: "https://auth-api.8slp.net/v1/tokens")!
    static let clientAPI = URL(string: "https://client-api.8slp.net/v1")!
    static let appAPI = URL(string: "https://app-api.8slp.net/v1")!

    /// Heating levels are unitless, -100 (cold) through 100 (hot). Ten is one
    /// watch tap, about two degrees Fahrenheit near the middle of the range.
    static let levelStep = 10
    static let levelMinimum = -100
    static let levelMaximum = 100

    /// Rapid taps collapse into the request that fires after this pause.
    static let debounceNanoseconds: UInt64 = 450_000_000

    /// Refresh a minute before the server's expiry, matching pyEight's buffer.
    static let tokenFreshnessBuffer: TimeInterval = 120
}
