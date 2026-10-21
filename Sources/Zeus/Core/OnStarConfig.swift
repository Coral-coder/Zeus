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
    /// Your GM account password. Stored in Keychain; required for the on-device
    /// B2C login and for unattended token re-auth (GM tokens expire).
    var password: String
    /// Your Bolt's VIN.
    var vin: String
    /// The TOTP shared secret (base32) from your authenticator-app MFA setup.
    /// Used to generate the 6-digit MFA code during login.
    var totpSecret: String
    /// A stable per-install device UUID. Generated once and stored in Keychain.
    var deviceId: String

    /// The OnStar PIN used to authorize remote commands (kept in Keychain).
    var commandPIN: String?

    /// Build a config for the browser-based login. Password and MFA are entered
    /// by the user in GM's official auth sheet, so they aren't stored here.
    static func makeNew(email: String, vin: String) -> OnStarConfig {
        OnStarConfig(email: email,
                     password: "",
                     vin: vin.uppercased(),
                     totpSecret: "",
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

    /// GraphQL "garage" endpoint that lists the account's vehicles.
    static var garageURL: URL { apiHost.appendingPathComponent("mbff/garage/v1") }

    /// Vehicle health-status (diagnostics) endpoint.
    static func healthStatusURL(vin: String) -> URL {
        apiHost.appendingPathComponent("api/v1/vh/vehiclehealth/v1/healthstatus/\(vin)")
    }

    static func commandURL(vin: String, command: String) -> URL {
        apiHost.appendingPathComponent("api/v1/account/vehicles/\(vin)/commands/\(command)")
    }

    /// The GraphQL query the mobile app sends to list vehicles.
    static let garageQuery =
        "query getVehiclesMBFF { vehicles { vin vehicleId make model nickName year imageUrl onstarCapable vehicleType roleCode } }"

    /// Common headers GM's mobile API expects on every authed request.
    static let commonHeaders: [String: String] = [
        "accept": "application/json",
        "accept-language": "en-US",
        "appversion": "myOwner-chevrolet-android-8.5.0-0",
        "locale": "en-US",
        "user-agent": "myOwner App",
        "push-request": "allow"
    ]
}
