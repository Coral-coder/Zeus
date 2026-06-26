import Foundation
import AuthenticationServices
import UIKit

/// Drives the on-device OAuth login against GM's Azure AD B2C tenant using
/// PKCE + `ASWebAuthenticationSession`. GM's own hosted login page renders
/// inside the secure web sheet, so **MFA / TOTP / passkeys are handled natively
/// by GM** — we never see or store the password, only the resulting tokens.
///
/// App target only (uses UIKit). PKCE and the token exchanges live in the
/// UIKit-free `GMTokenService` so the widget can refresh without this file.
@MainActor
final class GMAuthSession: NSObject {
    private let tokens = GMTokenService()

    /// Run the interactive login. Returns the GM API token on success.
    func login() async throws -> GMToken {
        let pkce = tokens.makePKCE()
        let state = tokens.randomState()
        let authURL = tokens.authorizeURL(challenge: pkce.challenge, state: state)
        let callback = try await present(authURL: authURL)

        guard let code = GMTokenService.queryItem(callback, "code") else {
            if let err = GMTokenService.queryItem(callback, "error_description") {
                throw OnStarError.authFailed(err)
            }
            throw OnStarError.authFailed("No authorization code returned.")
        }
        return try await tokens.exchange(code: code, verifier: pkce.verifier)
    }

    private func present(authURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: GMAPI.redirectScheme
            ) { callbackURL, error in
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        cont.resume(throwing: OnStarError.authCancelled)
                    } else {
                        cont.resume(throwing: OnStarError.authFailed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    cont.resume(throwing: OnStarError.authFailed("No callback URL."))
                    return
                }
                cont.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                cont.resume(throwing: OnStarError.authFailed("Couldn't start the login session."))
            }
        }
    }
}

extension GMAuthSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
