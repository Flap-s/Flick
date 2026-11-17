import SwiftUI

struct UpdateSettings: View {
    @ObservedObject private var updater = Updater.shared
    @AppStorage(UpdateKeys.autoCheckKey) private var autoCheck = true

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("Version installée", "Installed version"), value: updater.currentVersion)
                Toggle(tr("Rechercher les mises à jour automatiquement", "Check for updates automatically"), isOn: $autoCheck)
                    .onChange(of: autoCheck) { _, _ in updater.startAutomaticChecks() }
                if let repoURL = updater.repositoryURL, let repository = updater.repository {
                    LabeledContent("Source") { Link(repository, destination: repoURL) }
                }
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    status
                    Spacer()
                    Button(tr("Rechercher maintenant", "Check Now")) { Task { await updater.check(userInitiated: true) } }
                        .disabled(busy || updater.repository == nil)
                }
                if let last = updater.lastChecked {
                    Text(tr("Dernière vérification ", "Last checked ") + last.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let release = updater.availableRelease {
                Section("Flick \(release.version?.description ?? release.tagName)") {
                    ScrollView {
                        Text(release.body?.isEmpty == false ? release.body! : tr("Pas de notes de version.", "No release notes."))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 140)
                    HStack {
                        Link(tr("Voir sur GitHub", "View on GitHub"), destination: release.htmlUrl)
                        Spacer()
                        Button(tr("Télécharger et installer", "Download and Install")) { Task { await updater.install() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy)
                    }
                    Text(tr("Flick va quitter, se mettre à jour et se rouvrir. Vos réglages et autorisations sont conservés.", "Flick will quit, update itself and reopen. Your settings and permissions are kept."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var busy: Bool {
        [.checking, .downloading, .installing].contains(updater.state)
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle:
            Text(tr("Pas encore vérifié", "Not checked yet")).foregroundStyle(.secondary)
        case .checking:
            HStack { ProgressView().controlSize(.small); Text(tr("Recherche…", "Checking…")) }
        case .upToDate:
            Label(tr("Flick est à jour", "Flick is up to date"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let release):
            Label(tr("La version \(release.version?.description ?? release.tagName) est disponible", "Version \(release.version?.description ?? release.tagName) is available"), systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .downloading:
            HStack { ProgressView().controlSize(.small); Text(tr("Téléchargement…", "Downloading…")) }
        case .installing:
            HStack { ProgressView().controlSize(.small); Text(tr("Installation…", "Installing…")) }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
