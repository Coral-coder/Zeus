import Foundation

enum OnStarError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case authCancelled
    case authFailed(String)
    case tokenExchangeFailed(Int, String)
    case requestFailed(Int, String)
    case commandTimedOut(VehicleCommand)
    case commandFailed(VehicleCommand, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Zeus isn't linked to your OnStar account yet. Add your account in Settings."
        case .notAuthenticated:
            return "Your OnStar session expired. Please sign in again."
        case .authCancelled:
            return "Sign-in was cancelled."
        case .authFailed(let m):
            return "Sign-in failed: \(m)"
        case .tokenExchangeFailed(let code, let m):
            return "Couldn't get an access token (\(code)): \(m)"
        case .requestFailed(let code, let m):
            return "Request failed (\(code)): \(m)"
        case .commandTimedOut(let c):
            return "\(c.title) timed out. The car may be in a poor coverage area."
        case .commandFailed(let c, let m):
            return "\(c.title) failed: \(m)"
        case .decoding(let m):
            return "Couldn't read the response: \(m)"
        }
    }
}
