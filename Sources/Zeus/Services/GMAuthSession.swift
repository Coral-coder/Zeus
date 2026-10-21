import Foundation
import UIKit
import AuthenticationServices

/// Interactive on-device GM login using `ASWebAuthenticationSession`.
///
/// GM fronts its Azure B2C login with Akamai bot-detection, which fingerprints
/// and blocks plain `URLSession` traffic (HTTP 403 "Access Denied"). This driver
/// loads the *official* GM login page in Apple's real WebKit-backed auth sheet —
/// to Akamai it's genuine Safari, so it passes. The user signs in (email,
/// password, MFA) once; we capture the redirect's authorization code and trade
/// it (via `GMTokenService`) for the GM API token. After this one interactive
/// login, tokens refresh silently — no proxy, fully on-device.
@MainActor
final class GMAuthSession: NSObject {
    private let config: OnStarConfig
    private let tokens = GMTokenService()
    private var session: ASWebAuthenticationSession?

    init(config: OnStarConfig) {
        self.config = config
        super.init()
    }

    func authenticate() async throws -> GMToken {
        let pkce = tokens.makePKCE()
        let state = tokens.randomState()
        let authorizeURL = tokens.authorizeURL(challenge: pkce.challenge,
                                               state: state,
                                               loginHint: config.email)

        let callback = try await present(url: authorizeURL)

        if let code = GMTokenService.queryItem(callback, "code") {
            return try await tokens.exchange(code: code,
                                             verifier: pkce.verifier,
                                             deviceId: config.deviceId)
        }
        if let err = GMTokenService.queryItem(callback, "error_description")
            ?? GMTokenService.queryItem(callback, "error") {
            throw OnStarError.authFailed("GM login error: \(err)")
        }
        throw OnStarError.authFailed("No authorization code was returned from GM login.")
    }

    /// Present the system auth sheet and resume with the captured callback URL.
    private func present(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GMAPI.redirectScheme
            ) { callbackURL, error in
                if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        cont.resume(throwing: OnStarError.authFailed("Login was cancelled."))
                    } else {
                        cont.resume(throwing: error)
                    }
                } else {
                    cont.resume(throwing: OnStarError.authFailed("Login finished without a result."))
                }
            }
            session.presentationContextProvider = self
            // Keep cookies so a previously-trusted device can skip MFA next time.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                cont.resume(throwing: OnStarError.authFailed("Couldn't start the GM login session."))
            }
        }
    }
}

extension GMAuthSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
