import SwiftUI
import AppKit
import QuickLookThumbnailing

/// Aperçu Quick Look d'un fichier (ou son icône si aucun aperçu n'est disponible).
struct FileThumbnail: View {
    let url: URL
    var size = CGSize(width: 360, height: 280)

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 150, maxHeight: 150)
            }
        }
        .task(id: url) {
            image = nil
            image = await Self.thumbnail(for: url, size: size)
        }
    }

    static func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale,
                                                   representationTypes: .thumbnail)
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.nsImage
        } catch {
            return nil
        }
    }
}

/// La carte d'un fichier, façon Tinder.
struct FileCard: View {
    let url: URL
    let target: SortCategory
    var tint: Color = .green
    var size: CGSize = FileCard.size

    @State private var folderSummary: FolderSummary?
    private var isFolder: Bool { AppState.isFolder(url) }

    static let size = CGSize(width: 360, height: 460)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [tint.opacity(0.14), tint.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if isFolder {
                    FolderPreview(summary: folderSummary)
                        .padding(18)
                } else {
                    FileThumbnail(url: url)
                        .padding(22)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                NameArea(url: url)

                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: target.symbol)
                    Text("Proposé : \(target.name)")
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.14)))
                .foregroundStyle(tint)
                .help("Destination avec → : \(target.name)")

                AutoSortCountdown(url: url)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.14), radius: 28, y: 16)
        .task(id: url) {
            guard isFolder else { return }
            folderSummary = nil
            folderSummary = await FolderSummary.load(url)
        }
    }

    private var details: String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey,
                                                       .addedToDirectoryDateKey, .contentModificationDateKey])
        var parts: [String] = []
        if isFolder {
            parts.append("Dossier")
            if let summary = folderSummary {
                parts.append(summary.countDescription)
                if summary.totalSize > 0 {
                    parts.append(ByteCountFormatter.string(fromByteCount: summary.totalSize, countStyle: .file))
                }
            } else {
                parts.append("analyse…")
            }
            return parts.joined(separator: " · ")
        }
        let ext = url.pathExtension.uppercased()
        parts.append(ext.isEmpty ? "Sans extension" : ext)
        if let bytes = values?.fileSize ?? values?.totalFileAllocatedSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if let date = values?.addedToDirectoryDate ?? values?.contentModificationDate {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}

/// Le tampon « RANGER / GARDER / CORBEILLE » qui apparaît pendant le glissement.
struct SwipeStamp: View {
    let text: String
    let color: Color
    let angle: Double

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color, lineWidth: 4))
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor).opacity(0.85)))
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Dossiers

/// Résumé du contenu d'un dossier, calculé en arrière-plan.
struct FolderSummary {
    var items: [URL]          // premier niveau, triés (dossiers d'abord)
    var fileCount: Int        // fichiers, sous-dossiers compris
    var subfolderCount: Int   // sous-dossiers au premier niveau
    var totalSize: Int64
    var truncated: Bool

    var countDescription: String {
        if items.isEmpty { return "vide" }
        var parts: [String] = []
        let files = fileCount
        parts.append("\(files)\(truncated ? "+" : "") fichier\(files > 1 ? "s" : "")")
        if subfolderCount > 0 {
            parts.append("\(subfolderCount) sous-dossier\(subfolderCount > 1 ? "s" : "")")
        }
        return parts.joined(separator: ", ")
    }

    static func load(_ url: URL) async -> FolderSummary {
        await Task.detached(priority: .userInitiated) { compute(url) }.value
    }

    static func compute(_ url: URL) -> FolderSummary {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        let top = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys),
                                               options: [.skipsHiddenFiles])) ?? []
        func folder(_ u: URL) -> Bool {
            let v = try? u.resourceValues(forKeys: keys)
            return (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
        }
        let items = top.sorted { a, b in
            let fa = folder(a), fb = folder(b)
            if fa != fb { return fa }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        var total: Int64 = 0
        var files = 0
        var truncated = false
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
                                          options: [.skipsHiddenFiles]) {
            while let file = enumerator.nextObject() as? URL {
                guard let v = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]),
                      v.isRegularFile == true else { continue }
                files += 1
                total += Int64(v.fileSize ?? v.totalFileAllocatedSize ?? 0)
                if files >= 50_000 { truncated = true; break }
            }
        }
        return FolderSummary(items: items, fileCount: files,
                             subfolderCount: items.filter(folder).count,
                             totalSize: total, truncated: truncated)
    }
}

/// Mosaïque des premiers éléments d'un dossier, affichée sur sa carte.
struct FolderPreview: View {
    let summary: FolderSummary?

    var body: some View {
        if let summary {
            if summary.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Dossier vide")
                        .foregroundStyle(.secondary)
                }
            } else {
                let maxTiles = 9
                let overflow = summary.items.count > maxTiles
                let shown = Array(summary.items.prefix(overflow ? maxTiles - 1 : maxTiles))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(shown, id: \.self) { item in
                        VStack(spacing: 4) {
                            FileThumbnail(url: item, size: CGSize(width: 120, height: 120))
                                .frame(width: 58, height: 58)
                            Text(item.lastPathComponent)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if overflow {
                        VStack(spacing: 2) {
                            Text("+\(summary.items.count - shown.count)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("autres")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 58, height: 58)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    }
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}

/// Liste complète du contenu d'un dossier (aperçu en grand, touche Espace).
struct FolderContentsView: View {
    let url: URL
    @State private var summary: FolderSummary?

    var body: some View {
        Group {
            if let summary {
                if summary.items.isEmpty {
                    Text("Ce dossier est vide.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(summary.countDescription) · \(ByteCountFormatter.string(fromByteCount: summary.totalSize, countStyle: .file))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        List(summary.items, id: \.self) { item in
                            FolderItemRow(url: item)
                        }
                    }
                }
            } else {
                ProgressView("Analyse du dossier…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) { summary = await FolderSummary.load(url) }
    }
}

private struct FolderItemRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 10) {
            FileThumbnail(url: url, size: CGSize(width: 64, height: 64))
                .frame(width: 32, height: 32)
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(info)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .help("Double-clic pour ouvrir")
    }

    private var info: String {
        if AppState.isFolder(url) { return "Dossier" }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - Nom et renommage

/// Nom du fichier sur la carte, avec la proposition de l'IA et l'édition manuelle.
struct NameArea: View {
    @EnvironmentObject var state: AppState
    let url: URL

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var ext: String { AppState.isFolder(url) ? "" : url.pathExtension }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editing {
                editor
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(url.lastPathComponent)
                    Spacer(minLength: 4)
                    Button { startEditing() } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Renommer (R)")
                    .hoverPop(angle: -12)
                    if state.renameEnabled && !hasSuggestionOrAnalysis {
                        Button { state.requestRenameSuggestion(for: url) } label: {
                            Image(systemName: "sparkles")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.purple)
                        .help("Proposer un nom plus clair (I)")
                        .hoverPop(scale: 1.25, angle: 15)
                    }
                }
                suggestion
            }
        }
        .onChange(of: state.renameEditRequest) { request in
            guard request == url else { return }
            state.renameEditRequest = nil
            startEditing()
        }
    }

    private var hasSuggestionOrAnalysis: Bool {
        switch state.renameStates[url] {
        case .analyzing?, .suggested?: return true
        default: return false
        }
    }

    // Édition manuelle

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                TextField("Nouveau nom", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.weight(.semibold))
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                if !ext.isEmpty {
                    Text(".\(ext)")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text("↩ renommer · esc annuler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Annuler") { editing = false }
                    .controlSize(.small)
                Button("Renommer", action: commit)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func startEditing() {
        var proposal = url.lastPathComponent
        if case .suggested(let name, _)? = state.renameStates[url] { proposal = name }
        if !ext.isEmpty, proposal.lowercased().hasSuffix("." + ext.lowercased()) {
            proposal = String(proposal.dropLast(ext.count + 1))
        }
        draft = proposal
        editing = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func commit() {
        let name = ext.isEmpty ? draft : "\(draft).\(ext)"
        if state.rename(url, to: name) != nil {
            editing = false
        }
    }

    // Proposition de l'IA

    @ViewBuilder
    private var suggestion: some View {
        switch state.renameStates[url] {
        case .analyzing?:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(state.renameUsesAI ? "L'IA cherche un nom plus clair…" : "Recherche d'un nom plus clair…")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

        case .suggested(let name, let byAI)?:
            VStack(alignment: .leading, spacing: 10) {
                // Étiquette
                HStack(spacing: 6) {
                    Image(systemName: byAI ? "sparkles" : "wand.and.rays")
                        .font(.system(size: 11, weight: .bold))
                    Text(byAI ? "PROPOSÉ PAR APPLE INTELLIGENCE" : "NOM PROPOSÉ")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button { state.dismissRenameSuggestion(for: url) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Garder le nom actuel")
                    .hoverPop()
                }
                .foregroundStyle(Color.purple)

                // Le nom proposé, en grand
                Text(name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                // Actions, sur toute la largeur
                HStack(spacing: 8) {
                    SuggestionButton(title: "Utiliser", key: "N", prominent: true) {
                        state.applyRenameSuggestion(for: url)
                    }
                    SuggestionButton(title: "Modifier", key: "R", prominent: false) {
                        startEditing()
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color.purple.opacity(0.14), Color.purple.opacity(0.05)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.22))
            )

        case .noSuggestion(let message)?:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle")
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { state.requestRenameSuggestion(for: url) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Réessayer (I)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        default:
            EmptyView()
        }
    }
}

/// « Rangé automatiquement dans 2 h » quand le mode automatique est actif.
struct AutoSortCountdown: View {
    @EnvironmentObject var state: AppState
    let url: URL

    var body: some View {
        if let date = state.autoSortDate(for: url) {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                if date > Date() {
                    Text("Rangé automatiquement dans ") + Text(date, style: .relative).monospacedDigit()
                } else {
                    Text("Rangé automatiquement dans un instant")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Délai réglable dans Réglages → Rangement automatique")
        }
    }
}

/// Bouton de l'encadré « nom proposé » : jamais tronqué, touche intégrée.
private struct SuggestionButton: View {
    let title: String
    let key: String
    let prominent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                Text(key)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(prominent ? Color.white.opacity(0.22) : Color.primary.opacity(0.08))
                    )
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                Capsule().fill(prominent
                               ? AnyShapeStyle(LinearGradient(colors: [Color.purple.opacity(0.85), Color.purple],
                                                              startPoint: .top, endPoint: .bottom))
                               : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
            )
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Color.primary.opacity(0.12)))
            .shadow(color: prominent ? Color.purple.opacity(hovering ? 0.45 : 0.25) : .black.opacity(hovering ? 0.10 : 0.04),
                    radius: hovering ? 8 : 4, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) { hovering = h } }
    }
}
