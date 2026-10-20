import Foundation
import UIKit
import AuthenticationServices

/// Interactive Smartcar Connect login using `ASWebAuthenticationSession`.
///
/// Opens Smartcar's hosted OAuth page (the owner selects their brand — GM /
/// Chevrolet — and signs in to *their own* GM account on Smartcar's domain),
/// then captures the `?code=` on the redirect and hands it back so
/// `SmartcarClient` can exchange it for tokens. Zeus never sees the GM password.
@MainActor
final class SmartcarAuthSession: NSObject {
    private let authorizeURL: URL
    private let callbackScheme: String
    private var session: ASWebAuthenticationSession?

    /// - Parameters:
    ///   - authorizeURL: from `SmartcarClient.authorizeURL(state:)`.
    ///   - redirectURI: the app's registered redirect (e.g. "zeus://smartcar-callback").
    init(authorizeURL: URL, redirectURI: String) {
        self.authorizeURL = authorizeURL
        self.callbackScheme = URL(string: redirectURI)?.scheme ?? "zeus"
        super.init()
    }

    /// Present the system auth sheet and return the authorization `code`.
    func authorizeCode() async throws -> String {
        let callback = try await present(url: authorizeURL)
        let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
            return code
        }
        let err = comps?.queryItems?.first(where: { $0.name == "error_description" })?.value
            ?? comps?.queryItems?.first(where: { $0.name == "error" })?.value
        throw OnStarError.authFailed("Smartcar login error: \(err ?? "no code returned")")
    }

    private func present(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        cont.resume(throwing: OnStarError.authCancelled)
                    } else {
                        cont.resume(throwing: error)
                    }
                } else {
                    cont.resume(throwing: OnStarError.authFailed("Login finished without a result."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                cont.resume(throwing: OnStarError.authFailed("Couldn't start the Smartcar login session."))
            }
        }
    }
}

extension SmartcarAuthSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
