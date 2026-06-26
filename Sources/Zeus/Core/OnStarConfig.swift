import Foundation

/// Configuration for talking to GM's (unofficial) OnStar mobile API.
///
/// ⚠️ There is **no public GM API**. This client speaks the same private API
/// the MyChevrolet app uses, mirroring the well-maintained reverse-engineering
/// in the OnStarJS project (https://github.com/BigThunderSR/OnStarJS). GM
/// rotates client ids, scopes and the B2C tenant from time to time — when login
/// breaks, cross-check these constants against the latest OnStarJS release.
///
/// Using this may violate GM's Terms of Service. It's here for personal use
/// with your own vehicle and account.
struct OnStarConfig: Codable, Equatable {
    /// Your GM / MyChevrolet account email.
    var email: String
    /// Your Bolt's VIN.
    var vin: String
    /// A stable per-install device UUID. Generated once and stored in Keychain.
    var deviceId: String

    /// The OnStar PIN used to authorize remote commands (kept in Keychain).
    var commandPIN: String?

    static func makeNew(email: String, vin: String) -> OnStarConfig {
        OnStarConfig(email: email,
                     vin: vin.uppercased(),
                     deviceId: UUID().uuidString,
                     commandPIN: nil)
    }
}

/// Static GM B2C / API constants. Fill these from the current OnStarJS config.
/// Kept in one place so updates are a one-file change.
enum GMAPI {
    /// GM mobile API host.
    static let apiHost = URL(string: "https://na-mobile-api.gm.com")!

    /// Microsoft Azure AD B2C tenant GM authenticates against.
    static let b2cAuthorizeBase =
        "https://custlogin.gm.com/gmb2cprod.onmicrosoft.com/b2c_1a_seamless_mobile_signuporsignin/oauth2/v2.0"

    /// GM's mobile-app OAuth client id (public client; PKCE, no secret).
    /// Replace with the value from the current OnStarJS release if login fails.
    static let clientId = "3ff30506-d242-4bed-835b-422bf992622e"

    /// Custom redirect scheme registered by the GM app. We reuse it because GM
    /// exposes no public client. Must also appear in Info.plist CFBundleURLTypes.
    static let redirectURI = "msauth.com.gm.myChevrolet://auth"
    static let redirectScheme = "msauth.com.gm.mychevrolet"

    /// OAuth scopes requested for the mobile API token.
    static let scopes = [
        "https://gmb2cprod.onmicrosoft.com/3ff30506-d242-4bed-835b-422bf992622e/Test.Read",
        "openid", "profile", "offline_access"
    ]

    /// GM API token exchange endpoint (MS token -> GM API JWT).
    static var gmTokenURL: URL { apiHost.appendingPathComponent("sec/authz/v3/oauth/token") }

    static func vehiclesURL() -> URL {
        apiHost.appendingPathComponent("api/v1/account/vehicles")
    }

    static func commandURL(vin: String, command: String) -> URL {
        apiHost.appendingPathComponent("api/v1/account/vehicles/\(vin)/commands/\(command)")
    }
}
