import SwiftUI
import AppKit

/// Historique des fichiers rangés, avec possibilité d'annuler.
struct ActivityView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)
            Divider()
            if state.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Aucun fichier rangé pour l'instant")
                        .font(.headline)
                    Text("Va dans « À trier » pour commencer.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(state.history) { record in
                        HistoryRow(record: record)
                    }
                }
            }
        }
        .navigationTitle("Activité")
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: state.autoMode ? "bolt.circle.fill" : "hand.draw.fill")
                .font(.system(size: 34))
                .foregroundStyle(state.autoMode ? Color.yellow : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.autoMode ? "Rangement automatique actif" : "Tri manuel (swipe)")
                    .font(.headline)
                Text(state.watchedFolderDisplay)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let result = state.lastResult, let date = state.lastRun {
                    Text("\(result) · \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                state.organize(manual: true)
            } label: {
                Label("Tout ranger d'un coup", systemImage: "wand.and.stars")
            }
            .help("Range immédiatement tous les fichiers reconnus selon leur type")
        }
    }
}

struct HistoryRow: View {
    @EnvironmentObject var state: AppState
    let record: MoveRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: record.currentURL.path))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: record.undone ? "arrow.uturn.backward" : record.symbol)
                    Text(record.undone ? "Remis à sa place"
                         : record.categoryName == AppState.renamedLabel
                            ? "Renommé en « \(record.movedURL.lastPathComponent) »"
                            : "→ \(record.categoryName)")
                    Text("·")
                    Text(record.date.formatted(.relative(presentation: .named)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                state.reveal(record.currentURL)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Afficher dans le Finder")
            .hoverPop()

            if !record.undone {
                Button("Annuler") { state.undo(record) }
                    .buttonStyle(.borderless)
            }
        }
        .opacity(record.undone ? 0.55 : 1)
        .padding(.vertical, 3)
        .hoverHighlight()
    }
}
