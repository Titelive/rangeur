import SwiftUI

/// Édition des catégories : nom, dossier de destination et extensions.
struct RulesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Chaque fichier est proposé dans la première catégorie qui contient son extension. Les dossiers sont créés dans « \(state.watchedFolderDisplay) ».")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach($state.categories) { $category in
                    RuleRow(category: $category) {
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
    let onDelete: () -> Void

    @State private var extensionsText: String

    init(category: Binding<SortCategory>, onDelete: @escaping () -> Void) {
        _category = category
        self.onDelete = onDelete
        _extensionsText = State(initialValue: category.wrappedValue.extensions.joined(separator: ", "))
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
                    TextField("Dossier", text: $category.folder)
                        .frame(width: 150)
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
            }
            .padding(6)
        }
        .opacity(category.isEnabled ? 1 : 0.55)
        .hoverGlow(cornerRadius: 10)
    }
}
