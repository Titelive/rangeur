import SwiftUI
import AppKit

/// Édition des catégories : nom, dossier de destination et extensions.
struct RulesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Chaque fichier est proposé dans la première catégorie qui contient son extension. Les fichiers sont rangés dans de vrais dossiers du Mac (~/Pictures, ~/Documents…) ; un nom simple comme « Archives » crée un sous-dossier dans « \(state.watchedFolderDisplay) ». Une archive ou une image disque dont le nom contient un mot-clé (ex. « Switch NSP ») est proposée dans la catégorie de ce mot-clé.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach($state.categories) { $category in
                    RuleRow(category: $category, destination: state.folderDisplay(for: category.folder)) {
                        state.removeCategory(category.id)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("En mode automatique, ranger aussi les fichiers non reconnus", isOn: $state.moveUnknown)
                        HStack {
                            Text("Dossier pour les fichiers non reconnus :")
                            TextField("Divers", text: $state.unknownFolderName)
                                .frame(width: 160)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Fichiers non reconnus", systemImage: "questionmark.folder")
                }
            }
            .padding(20)
        }
        .navigationTitle("Catégories")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    state.addCategory()
                } label: {
                    Label("Nouvelle catégorie", systemImage: "plus")
                }
                Button("Réinitialiser") {
                    state.resetCategories()
                }
                .help("Revenir aux catégories proposées par défaut")
            }
        }
    }
}

struct RuleRow: View {
    @Binding var category: SortCategory
    let destination: String
    let onDelete: () -> Void

    @State private var extensionsText: String
    @State private var keywordsText: String

    init(category: Binding<SortCategory>, destination: String, onDelete: @escaping () -> Void) {
        _category = category
        self.destination = destination
        self.onDelete = onDelete
        _extensionsText = State(initialValue: category.wrappedValue.extensions.joined(separator: ", "))
        _keywordsText = State(initialValue: (category.wrappedValue.keywords ?? []).joined(separator: ", "))
    }

    /// Choisir le dossier de destination dans le Finder.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Ranger ici"
        panel.message = "Où ranger les fichiers « \(category.name) » ?"
        if panel.runModal() == .OK, let url = panel.url {
            category.folder = (url.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Toggle("Active", isOn: $category.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Image(systemName: category.symbol)
                        .frame(width: 22)
                        .foregroundStyle(Color.accentColor)
                    TextField("Nom", text: $category.name)
                        .textFieldStyle(.plain)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    TextField("~/Pictures ou Archives", text: $category.folder)
                        .frame(width: 190)
                        .help("Rangé dans : \(destination)")
                    Button("Choisir…", action: chooseFolder)
                        .help("Choisir le dossier dans le Finder")
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Supprimer cette catégorie")
                    .hoverPop(angle: -8)
                }
                TextField("Extensions, ex. : jpg, png, heic", text: $extensionsText)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: extensionsText) { newValue in
                        category.extensions = SortCategory.parseExtensions(newValue)
                    }
                TextField("Mots-clés dans le nom (archives, images disque), ex. : switch, nsp, ps2", text: $keywordsText)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: keywordsText) { newValue in
                        category.keywords = newValue
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                            .filter { !$0.isEmpty }
                    }
                Text("Rangé dans \(destination)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
        .opacity(category.isEnabled ? 1 : 0.55)
        .hoverGlow(cornerRadius: 10)
    }
}
