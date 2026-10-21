import SwiftUI
import UniformTypeIdentifiers

/// The hidden sideloader panel: stage an `.ipa` from any of four sources and
/// install it over-the-air on this device. Reached by long-pressing the ZEUS
/// logo on the home screen.
struct SideloadView: View {
    @EnvironmentObject private var sideload: SideloadModel

    @State private var showFileImporter = false
    @State private var showURLPrompt = false
    @State private var urlText = ""
    @State private var showTrust = false
    @State private var showSignIn = false
    @State private var showUDIDPrompt = false
    @State private var udidText = ""

    private var ipaContentTypes: [UTType] {
        if let t = UTType(filenameExtension: "ipa") { return [t] }
        return [.data]
    }

    var body: some View {
        ZStack {
            AeroBackground(animated: false)

            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    trustCard
                    sourcesCard
                    if sideload.installs.isEmpty {
                        emptyHint
                    } else {
                        installsCard
                    }
                    footnote
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Sideload")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sideload.startServer(); sideload.refreshEnrollment() }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: ipaContentTypes,
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                sideload.handleIncoming(url)
            }
        }
        .alert("Install from URL", isPresented: $showURLPrompt) {
            TextField("https://…/App.ipa", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Download") { let u = urlText; Task { await sideload.stageFromURL(u) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a link to an .ipa (or a zip containing one).")
        }
        .sheet(isPresented: $showTrust) {
            NavigationStack {
                TrustView().environmentObject(sideload)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showTrust = false } } }
            }
        }
        .sheet(isPresented: $showSignIn) {
            NavigationStack {
                SignInView().environmentObject(sideload)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showSignIn = false } } }
            }
        }
        .alert("Enter device UDID", isPresented: $showUDIDPrompt) {
            TextField("00008030-000…  or  40 hex chars", text: $udidText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Set") { sideload.setManualUDID(udidText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste this device's UDID. Get it from your Apple Developer account (Devices) or a UDID service — then Zeus registers it and signs for this device.")
        }
    }

    // MARK: - Sections

    private var statusCard: some View {
        GlassCard(glow: sideload.serverReady ? Aero.aurora : Aero.ember) {
            HStack(spacing: 12) {
                if sideload.busy { ProgressView().tint(Aero.bolt) }
                VStack(alignment: .leading, spacing: 4) {
                    StatusPill(text: sideload.serverReady ? "Server ready" : "Server off",
                               systemImage: sideload.serverReady ? "checkmark.seal.fill" : "pause.circle.fill",
                               color: sideload.serverReady ? Aero.aurora : Aero.ember)
                    Text(sideload.status)
                        .font(.aeroCaption)
                        .foregroundStyle(Aero.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var trustCard: some View {
        GlassCard(glow: sideload.signedIn ? Aero.aurora : Aero.iris) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Setup (once)", systemImage: "lock.shield", tint: Aero.iris)

                setupRow(number: 1, done: sideload.signedIn,
                         title: sideload.signedIn ? "Signed in" : "Sign in with your developer account") {
                    showSignIn = true
                }
                // Trust MUST come before enrollment: the enroll profile posts the
                // UDID back over HTTPS, and iOS validates Zeus's cert at that
                // moment ("MDM server certificate invalid" if it isn't trusted).
                setupRow(number: 2, done: false, title: "Trust Zeus's certificate") { showTrust = true }
                setupRow(number: 3, done: sideload.udid != nil,
                         title: sideload.udid != nil ? "Device enrolled" : "Enroll this device (get UDID)") {
                    sideload.openEnroll()
                }

                Text("Do these in order — Trust before Enroll. Then every build you add is signed for your device and installed automatically.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Aero.textTertiary)

                if sideload.udid == nil {
                    Button("Enrollment failing? Enter UDID manually") { udidText = ""; showUDIDPrompt = true }
                        .font(.aeroCaption)
                        .foregroundStyle(Aero.bolt)
                }
            }
        }
    }

    private func setupRow(number: Int, done: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(done ? Aero.aurora : Aero.textTertiary)
                Text(title).font(.aeroBody).foregroundStyle(.white)
                Spacer()
                if !done {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Aero.textTertiary)
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
        }
    }

    private var sourcesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Add a build", systemImage: "tray.and.arrow.down.fill", tint: Aero.bolt)
                Button { showFileImporter = true } label: {
                    sourceRow("Choose an .ipa file", "folder.fill")
                }
                Button { urlText = ""; showURLPrompt = true } label: {
                    sourceRow("Install from a URL", "link")
                }
                NavigationLink {
                    GitHubBrowserView().environmentObject(sideload)
                } label: {
                    sourceRow("Browse GitHub artifacts", "shippingbox.fill")
                }
                Text("Or open an .ipa from Files / Share and choose Zeus.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Aero.textTertiary)
            }
        }
    }

    private func sourceRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Aero.bolt)
                .frame(width: 26)
            Text(title).font(.aeroBody).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Aero.textTertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.10)))
    }

    private var installsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Staged builds", systemImage: "square.and.arrow.down.on.square.fill", tint: Aero.aurora)
                ForEach(sideload.installs) { install in
                    installRow(install)
                }
            }
        }
    }

    private func installRow(_ install: SideloadInstall) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(install.title).font(.aero(17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
            Text("\(install.bundleID) · v\(install.version) · \(sizeString(install.sizeBytes))")
                .font(.aeroCaption).foregroundStyle(Aero.textSecondary).lineLimit(1)
            HStack(spacing: 10) {
                Button("Install") { sideload.install(install) }
                    .buttonStyle(GlossyButtonStyle(gradient: Aero.chargeGradient, glow: Aero.aurora))
                Button(role: .destructive) { sideload.delete(install) } label: {
                    Image(systemName: "trash").font(.system(size: 16, weight: .semibold)).foregroundStyle(Aero.flare)
                        .padding(12)
                        .background(Circle().fill(.ultraThinMaterial))
                        .overlay(Circle().strokeBorder(Aero.flare.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.10)))
    }

    private var emptyHint: some View {
        Text("No builds staged yet.")
            .font(.aeroCaption)
            .foregroundStyle(Aero.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private var footnote: some View {
        Text("The .ipa must be signed for THIS device (Ad Hoc / Development with your UDID in the profile). Zeus serves it as-is — it does not re-sign.")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Aero.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
    }

    private func sizeString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
