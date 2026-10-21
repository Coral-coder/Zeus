import Foundation

/// Thin wrapper over the GitHub REST API for listing and downloading Actions
/// artifacts. Native port of `ipa_sideload`'s `src/github.js`.
struct GitHubService {
    var token: String

    struct Viewer { let login: String }
    struct Repo: Identifiable, Hashable {
        var id: String { fullName }
        let fullName: String
        let isPrivate: Bool
    }
    struct Artifact: Identifiable, Hashable {
        let id: Int
        let name: String
        let sizeBytes: Int
        let createdAt: String
        let branch: String?
        let commit: String?
    }

    enum GitHubError: LocalizedError {
        case http(Int, String)
        case decode
        var errorDescription: String? {
            switch self {
            case .http(let code, let msg): return "GitHub API \(code): \(msg)"
            case .decode: return "Unexpected response from GitHub."
            }
        }
    }

    private let api = URL(string: "https://api.github.com")!

    private func request(_ path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: path, relativeTo: api)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("zeus-sideload", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func send(_ path: String) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: request(path))
        guard let http = resp as? HTTPURLResponse else { throw GitHubError.decode }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.http(http.statusCode, String(body.prefix(300)))
        }
        return data
    }

    private func json(_ path: String) async throws -> Any {
        try JSONSerialization.jsonObject(with: try await send(path))
    }

    /// Validate the token.
    func viewer() async throws -> Viewer {
        guard let obj = try await json("/user") as? [String: Any],
              let login = obj["login"] as? String else { throw GitHubError.decode }
        return Viewer(login: login)
    }

    /// Repos the token can see, most-recently-pushed first.
    func repos() async throws -> [Repo] {
        guard let arr = try await json("/user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member") as? [[String: Any]] else {
            throw GitHubError.decode
        }
        return arr.compactMap { r in
            guard let full = r["full_name"] as? String else { return nil }
            return Repo(fullName: full, isPrivate: (r["private"] as? Bool) ?? false)
        }
    }

    /// Non-expired Actions artifacts for a repo, newest first.
    func artifacts(owner: String, repo: String) async throws -> [Artifact] {
        guard let obj = try await json("/repos/\(owner)/\(repo)/actions/artifacts?per_page=100") as? [String: Any],
              let arr = obj["artifacts"] as? [[String: Any]] else { throw GitHubError.decode }
        return arr.compactMap { a in
            guard let id = a["id"] as? Int, ((a["expired"] as? Bool) ?? false) == false else { return nil }
            let run = a["workflow_run"] as? [String: Any]
            return Artifact(
                id: id,
                name: a["name"] as? String ?? "artifact",
                sizeBytes: a["size_in_bytes"] as? Int ?? 0,
                createdAt: a["created_at"] as? String ?? "",
                branch: run?["head_branch"] as? String,
                commit: (run?["head_sha"] as? String).map { String($0.prefix(7)) }
            )
        }
    }

    /// Download an artifact's zip into memory (an .ipa is tens of MB).
    func downloadArtifactZip(owner: String, repo: String, artifactID: Int) async throws -> Data {
        try await send("/repos/\(owner)/\(repo)/actions/artifacts/\(artifactID)/zip")
    }
}
