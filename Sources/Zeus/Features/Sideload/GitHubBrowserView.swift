import SwiftUI

/// Browse a GitHub repo's Actions artifacts and stage the `.ipa` inside.
/// Native port of `ipa_sideload`'s GitHub-artifact flow (`src/github.js`).
struct GitHubBrowserView: View {
    @EnvironmentObject private var sideload: SideloadModel

    @State private var token = ""
    @State private var login: String?
    @State private var repos: [GitHubService.Repo] = []
    @State private var loading = false
    @State private var error: String?

    private var service: GitHubService { GitHubService(token: token) }

    var body: some View {
        ZStack {
            AeroBackground(animated: false)
            ScrollView {
                VStack(spacing: 20) {
                    tokenCard
                    if let error { errorCard(error) }
                    if !repos.isEmpty { reposCard }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle("GitHub Artifacts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if token.isEmpty, let saved = KeychainStore.load(String.self, for: .githubToken) { token = saved }
        }
    }

    private var tokenCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Access token", systemImage: "key.fill", tint: Aero.bolt)
                SecureField("ghp_… (Contents+Actions: Read)", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    .foregroundStyle(.white)
                if let login {
                    StatusPill(text: "Signed in as \(login)", systemImage: "person.fill", color: Aero.aurora)
                }
                Button(loading ? "Connecting…" : "Connect") { connect() }
                    .buttonStyle(GlossyButtonStyle())
                    .disabled(token.isEmpty || loading)
            }
        }
    }

    private var reposCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Repositories", systemImage: "folder.fill", tint: Aero.aurora)
                ForEach(repos) { repo in
                    NavigationLink {
                        RepoArtifactsView(service: service, repo: repo).environmentObject(sideload)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: repo.isPrivate ? "lock.fill" : "shippingbox.fill")
                                .foregroundStyle(Aero.bolt).frame(width: 22)
                            Text(repo.fullName).font(.aeroBody).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Aero.textTertiary)
                        }
                        .padding(.vertical, 9).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
                    }
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Text(message).font(.aeroCaption).foregroundStyle(Aero.flare)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func connect() {
        error = nil
        loading = true
        try? KeychainStore.save(token, for: .githubToken)
        Task {
            defer { loading = false }
            do {
                let svc = service
                login = try await svc.viewer().login
                repos = try await svc.repos()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Lists a single repo's non-expired artifacts; tapping one stages it.
private struct RepoArtifactsView: View {
    let service: GitHubService
    let repo: GitHubService.Repo
    @EnvironmentObject private var sideload: SideloadModel
    @Environment(\.dismiss) private var dismiss

    @State private var artifacts: [GitHubService.Artifact] = []
    @State private var loading = true
    @State private var error: String?

    private var owner: String { repo.fullName.split(separator: "/").first.map(String.init) ?? "" }
    private var name: String { repo.fullName.split(separator: "/").last.map(String.init) ?? "" }

    var body: some View {
        ZStack {
            AeroBackground(animated: false)
            ScrollView {
                VStack(spacing: 16) {
                    if loading { ProgressView().tint(Aero.bolt).padding(.top, 40) }
                    if let error {
                        Text(error).font(.aeroCaption).foregroundStyle(Aero.flare)
                    }
                    if !artifacts.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Artifacts", systemImage: "shippingbox.fill", tint: Aero.aurora)
                                ForEach(artifacts) { artifact in
                                    Button { pick(artifact) } label: { row(artifact) }
                                }
                            }
                        }
                    } else if !loading && error == nil {
                        Text("No unexpired artifacts in this repo.")
                            .font(.aeroCaption).foregroundStyle(Aero.textTertiary).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ artifact: GitHubService.Artifact) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.name).font(.aeroBody).foregroundStyle(.white).lineLimit(1)
                Text([artifact.branch, artifact.commit].compactMap { $0 }.joined(separator: " · "))
                    .font(.aeroCaption).foregroundStyle(Aero.textSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "square.and.arrow.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(Aero.bolt)
        }
        .padding(.vertical, 9).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { artifacts = try await service.artifacts(owner: owner, repo: name) }
        catch { self.error = error.localizedDescription }
    }

    private func pick(_ artifact: GitHubService.Artifact) {
        Task {
            await sideload.stageFromGitHub(service, owner: owner, repo: name, artifact: artifact)
            dismiss()
        }
    }
}
