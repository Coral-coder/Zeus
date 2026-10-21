import Foundation

/// Where an `.ipa` came from — used only for a human-readable label on the
/// staged install (mirrors the `source` field in `ipa_sideload`'s store).
enum IPASource {
    case file(name: String)
    case url(String)
    case github(owner: String, repo: String, artifact: String)

    var label: String {
        switch self {
        case .file(let name): return "File · \(name)"
        case .url(let url): return "URL · \(url)"
        case .github(let owner, let repo, let artifact): return "GitHub · \(owner)/\(repo) · \(artifact)"
        }
    }
}
