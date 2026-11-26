import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Dossier à trier") {
                LabeledContent("Dossier") {
                    Text(state.watchedFolderDisplay)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }
                HStack {
                    Button("Choisir un autre dossier…") { state.chooseFolder() }
                    Button("Revenir à Téléchargements") {
                        state.selectFolder(URL(fileURLWithPath: AppState.defaultDownloadsPath, isDirectory: true))
                    }
                    .disabled(state.watchedFolderPath == AppState.defaultDownloadsPath)
                    Spacer()
                    Button("Ouvrir dans le Finder") { state.open(state.watchedFolderURL) }
                }
            }

            Section {
                Toggle("Ranger automatiquement les nouveaux fichiers", isOn: $state.autoMode)
                Picker("Délai avant de ranger", selection: $state.delaySeconds) {
                    ForEach(AppState.delayPresets.indices, id: \.self) { i in
                        Text(AppState.delayPresets[i].1).tag(AppState.delayPresets[i].0)
                    }
                    if !AppState.delayPresets.contains(where: { $0.0 == state.delaySeconds }) {
                        Text(AppState.delayLabel(state.delaySeconds)).tag(state.delaySeconds)
                    }
                }
                .disabled(!state.autoMode)
            } header: {
                Text("Rangement automatique")
            } footer: {
                Text("Désactivé, tu tries toi-même chaque fichier dans « À trier ». Activé, Rangeur range les fichiers reconnus une fois ce délai passé depuis leur arrivée : tu as le temps de t'en servir avant. En attendant, ils restent dans les cartes avec un compte à rebours, et tu peux toujours les trier toi-même. Un téléchargement en cours n'est jamais touché.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Nouveaux fichiers à trier", isOn: $state.notifyNewFiles)
                Toggle("Fichiers rangés automatiquement (avec bouton « Annuler »)", isOn: $state.notifyAutoSort)
                Toggle("Pastille sur l'icône du Dock", isOn: $state.showDockBadge)
                HStack {
                    Text("État : \(state.notificationStatus)")
                        .foregroundStyle(state.notificationsDenied ? Color.orange : Color.secondary)
                    Spacer()
                    if state.notificationsDenied {
                        Button("Ouvrir Réglages Système…") { Notifier.openSystemSettings() }
                    }
                    Button("Tester") { state.sendTestNotification() }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Aucune notification n'est envoyée quand la fenêtre de Rangeur est au premier plan. Les fichiers qui arrivent ensemble sont regroupés en une seule notification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Proposer aussi les dossiers au tri", isOn: $state.includeFolders)
            } header: {
                Text("Dossiers")
            } footer: {
                Text("Un dossier est proposé dans la catégorie de la majorité de ses fichiers (ex. un dossier de photos → Images), sinon dans « Dossiers ». Les dossiers de catégories créés par Rangeur ne sont jamais proposés, et le mode automatique ne déplace jamais de dossier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Proposer des noms plus clairs", isOn: $state.renameEnabled)
                Toggle("Lire le contenu des fichiers (texte, PDF, texte dans les images)", isOn: $state.renameReadContent)
                    .disabled(!state.renameEnabled)
                Picker("Date au début des noms", selection: $state.renameDateMode) {
                    ForEach(RenameDateMode.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!state.renameEnabled)
                Text("Factures, reçus, devis : la date du document, lue dans le PDF (2026-10-28 Facture EDF). Bulletins de paie : le mois de la période (2026-10 Bulletin de paie Acme).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Appliquer automatiquement le nom proposé quand je range", isOn: $state.renameAutoApply)
                    .disabled(!state.renameEnabled)
                Label(state.renameAIStatus, systemImage: state.renameUsesAI ? "sparkles" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(state.renameUsesAI ? Color.purple : Color.secondary)
            } header: {
                Text("Renommage")
            } footer: {
                Text("Les noms peu clairs (IMG_1234, identifiants aléatoires, « document (3) »…) sont analysés automatiquement ; I demande une proposition pour n'importe quel fichier, N l'accepte, R permet d'écrire ton propre nom. Tout se fait sur ton Mac, et chaque renommage s'annule avec ⌘Z.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Démarrage") {
                Toggle("Ouvrir Rangeur à l'ouverture de session", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Text("Fermer la fenêtre ne quitte pas l'app : Rangeur reste disponible dans la barre des menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if state.exceptions.isEmpty {
                    Text("Aucune exception pour l'instant.")
                        .foregroundStyle(.secondary)
                }
                ForEach($state.exceptions) { $rule in
                    ExceptionRow(rule: $rule) { state.removeException(rule.id) }
                }
                HStack {
                    Button {
                        state.addException()
                    } label: {
                        Label("Ajouter une exception", systemImage: "plus")
                    }
                    Spacer()
                    Menu("Exemples") {
                        Button("Torrents (.torrent)") { state.addException(".torrent") }
                        Button("Installeurs (.dmg) à garder sous la main") { state.addException(".dmg") }
                        Button("Factures : ne jamais renommer") { state.addException("Facture*", scope: .noRename) }
                        Button("Captures d'écran : ne jamais renommer") { state.addException("Capture d'écran*", scope: .noRename) }
                    }
                    .fixedSize()
                }
            } header: {
                Text("Exceptions")
            } footer: {
                Text("« .dmg » vise une extension. « Facture* » vise les noms qui commencent par Facture, « *devis* » ceux qui contiennent devis ; un mot seul est cherché n'importe où dans le nom. Les majuscules ne comptent pas. « Ne jamais proposer » : le fichier reste où il est et n'apparaît pas dans les cartes, ni dans le rangement automatique. « Ne jamais renommer » : pas de proposition de nom automatique (I reste possible).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if state.keptItems.isEmpty {
                    Text("Aucun fichier gardé. Un swipe à gauche (←) en ajoute ici.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.keptItems, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(url.path)
                            Spacer()
                            Button("Reproposer") { state.unkeep(url) }
                                .controlSize(.small)
                        }
                        .hoverHighlight(inset: -6)
                    }
                    HStack {
                        Spacer()
                        Button("Tout reproposer") { state.resetKeptFiles() }
                    }
                }
            } header: {
                Text("Fichiers gardés (\(state.keptCount))")
            }

            Section("À propos") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                        .hoverPop(scale: 1.12, angle: -6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rangeur").font(.headline)
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · gratuit, sans pub, sans compte")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("Créé par Titelive", destination: Links.author)
                            .font(.caption)
                    }
                    Spacer()
                    Button("Site de Rangeur") { NSWorkspace.shared.open(Links.site) }
                    CoffeeButton { NSWorkspace.shared.open(Links.coffee) }
                        .fixedSize()
                }
            }

            Section("Historique") {
                HStack {
                    Text("\(state.history.count) déplacement\(state.history.count > 1 ? "s" : "") dans l'historique")
                    Spacer()
                    Button("Effacer l'historique", role: .destructive) { state.clearHistory() }
                        .disabled(state.history.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshNotificationStatus() }
        .navigationTitle("Réglages")
    }
}

/// Une ligne d'exception : motif, portée, nombre de fichiers concernés, suppression.
private struct ExceptionRow: View {
    @EnvironmentObject var state: AppState
    @Binding var rule: ExceptionRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: rule.scope == .ignore ? "eye.slash" : "pencil.slash")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("", text: $rule.pattern, prompt: Text("ex. .torrent, Facture*, *devis*"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Picker("", selection: $rule.scope) {
                ForEach(ExceptionRule.Scope.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            let n = state.matchCount(for: rule)
            Text(rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "\(n) ici")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .help("Éléments du dossier trié concernés")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Supprimer cette exception")
            .hoverPop(angle: -8)
        }
        .hoverHighlight(inset: -6)
    }
}
