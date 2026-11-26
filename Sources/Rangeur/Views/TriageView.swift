import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Quartz

enum SwipeDirection {
    case right   // ranger
    case left    // garder
    case up      // corbeille
}

/// L'écran « À trier » : une pile de cartes à faire glisser.
struct TriageView: View {
    @EnvironmentObject var state: AppState

    @State private var offset: CGSize = .zero
    @State private var leaving: URL?
    @State private var keyMonitor: Any?
    @State private var showPreview = false
    @State private var pressedKey: SwipeDirection?
    @State private var dropTargeted = false

    private let threshold: CGFloat = 120

    var body: some View {
        VStack(spacing: 18) {
            header

            GeometryReader { geo in
                // La carte s'adapte à la hauteur disponible : rien ne déborde en bas.
                let height = min(480, max(260, geo.size.height - 28))
                let cardSize = CGSize(width: (height * 0.78).rounded(), height: height.rounded())
                ZStack {
                    if state.queue.isEmpty {
                        emptyState
                    } else {
                        // Les 3 premières cartes, dessinées de la dernière à la première.
                        ForEach(Array(state.queue.prefix(3).reversed()), id: \.self) { url in
                            card(for: url, depth: state.queue.firstIndex(of: url) ?? 0, size: cardSize)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.queue)

            if let top = state.queue.first {
                controls(for: top)
                KeyLegend()
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background(TriageBackground())
        .overlay { if dropTargeted { dropOverlay } }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .navigationTitle("À trier")
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .sheet(isPresented: $showPreview) {
            if let url = state.queue.first {
                PreviewSheet(url: url) { showPreview = false }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    state.undoLast()
                } label: {
                    Label("Annuler", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!state.canUndo)
                .help("Annuler le dernier tri (⌘Z)")
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(state.queue.isEmpty
                         ? "Tout est rangé"
                         : "\(state.queue.count) à trier")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.queue.count)
                    FolderPicker()
                }
                Text("Glisse la carte, ou joue au clavier avec ← ↑ →")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.sortedThisSession > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                    Text("\(state.sortedThisSession) trié\(state.sortedThisSession > 1 ? "s" : "")")
                        .monospacedDigit()
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassOr(Capsule(), tint: Color.orange.opacity(0.18)) {
                    Capsule().fill(Color.orange.opacity(0.12))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: Cartes

    private func target(for url: URL) -> SortCategory {
        state.target(for: url)
    }

    private func tint(for category: SortCategory) -> Color {
        if let index = state.categories.firstIndex(where: { $0.id == category.id }) {
            return CategoryTileLabel.color(for: index)
        }
        return .gray
    }

    @ViewBuilder
    private func card(for url: URL, depth: Int, size: CGSize) -> some View {
        let isTop = depth == 0
        let destination = target(for: url)
        FileCard(url: url, target: destination, tint: tint(for: destination), size: size)
            .overlay(alignment: .top) {
                if isTop { stamp(for: url) }
            }
            .scaleEffect(isTop ? 1 : 1 - CGFloat(depth) * 0.05)
            .offset(y: isTop ? 0 : CGFloat(depth) * 14)
            .opacity(isTop ? 1 : 1 - Double(depth) * 0.25)
            .offset(isTop ? offset : .zero)
            .rotationEffect(.degrees(isTop ? Double(offset.width / 20) : 0), anchor: .bottom)
            .gesture(drag(url))
            .onTapGesture(count: 2) { state.open(url) }
            .allowsHitTesting(isTop && leaving == nil)
            .zIndex(Double(10 - depth))
    }

    private func direction(of translation: CGSize, threshold: CGFloat) -> SwipeDirection? {
        if -translation.height > abs(translation.width), translation.height < -threshold { return .up }
        if translation.width > threshold { return .right }
        if translation.width < -threshold { return .left }
        return nil
    }

    @ViewBuilder
    private func stamp(for url: URL) -> some View {
        let strength = min(1, max(abs(offset.width), -offset.height) / threshold)
        switch direction(of: offset, threshold: 20) {
        case .right:
            SwipeStamp(text: "→ \(target(for: url).name.uppercased())", color: .green, angle: -12)
                .opacity(strength)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
        case .left:
            SwipeStamp(text: "GARDER", color: .blue, angle: 12)
                .opacity(strength)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(28)
        case .up:
            SwipeStamp(text: "CORBEILLE", color: .red, angle: 0)
                .opacity(strength)
                .padding(.top, 120)
        case nil:
            EmptyView()
        }
    }

    private func drag(_ url: URL) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard leaving == nil else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard leaving == nil else { return }
                // Moyenne entre la position et l'élan : un petit « flick » rapide suffit.
                let t = value.translation
                let p = value.predictedEndTranslation
                let blended = CGSize(width: (t.width + p.width) / 2, height: (t.height + p.height) / 2)
                if let dir = direction(of: blended, threshold: threshold) {
                    commit(dir, url)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = .zero }
                }
            }
    }

    /// Fait partir la carte dans la bonne direction, puis applique l'action.
    private func commit(_ direction: SwipeDirection, _ url: URL, into category: SortCategory? = nil) {
        guard leaving == nil else { return }
        leaving = url
        showPreview = false
        pressedKey = direction
        let flyTo: CGSize
        switch direction {
        case .right: flyTo = CGSize(width: 1000, height: offset.height + 80)
        case .left:  flyTo = CGSize(width: -1000, height: offset.height + 80)
        case .up:    flyTo = CGSize(width: offset.width, height: -1100)
        }
        withAnimation(.easeIn(duration: 0.22)) { offset = flyTo }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
            switch direction {
            case .right: state.sort(url, into: category ?? target(for: url))
            case .left:  state.keep(url)
            case .up:    state.trash(url)
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { offset = .zero }
            leaving = nil
            pressedKey = nil
        }
    }

    // MARK: Glisser-déposer un dossier

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.accentColor.opacity(0.08)))
            .overlay {
                Label("Dépose un dossier pour trier son contenu", systemImage: "folder.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(10)
            .allowsHitTesting(false)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            guard let url else { return }
            DispatchQueue.main.async {
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                // Un fichier déposé : on trie le dossier qui le contient.
                state.selectFolder(isDirectory.boolValue ? url : url.deletingLastPathComponent())
            }
        }
        return true
    }

    // MARK: Clavier

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Renvoie `nil` quand la touche a été utilisée pour le tri.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // ⌘, ⌃, ⌥ : on laisse passer (⌘Z, ⌘Q, etc.).
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
        // On ne vole pas les touches pendant qu'on écrit dans un champ texte.
        if event.window?.firstResponder is NSText { return event }
        // Sur l'écran de tri, les flèches servent uniquement au swipe : elles ne doivent jamais
        // faire défiler la barre latérale (sinon ↓ ouvre « Activité »), même quand la pile est vide.
        let isArrow = (123...126).contains(event.keyCode)
        guard let url = state.queue.first else { return isArrow ? nil : event }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        var action: (() -> Void)?

        switch event.keyCode {
        case 124:              action = { commit(.right, url) }          // →
        case 123:              action = { commit(.left, url) }           // ←
        case 126, 51, 117:     action = { commit(.up, url) }             // ↑, ⌫, ⌦
        case 49:               action = { showPreview.toggle() }         // Espace
        case 36, 76:           action = { state.open(url) }              // Entrée
        case 53 where showPreview: action = { showPreview = false }      // Échap
        case 125:              return nil                                // ↓ : neutralisée
        default:
            switch key {
            case "d", "l":     action = { commit(.right, url) }
            case "a", "q", "h": action = { commit(.left, url) }
            case "w", "z", "k": action = { commit(.up, url) }
            case "u":          action = { state.undoLast() }
            case "r":          action = { state.renameEditRequest = url }          // renommer
            case "n":          action = { state.applyRenameSuggestion(for: url) }  // nom proposé
            case "i":          action = { state.requestRenameSuggestion(for: url) } // demander à l'IA
            default:
                if let digit = Int(key), (1...9).contains(digit) {
                    let categories = state.categories.filter { $0.isEnabled }
                    if digit <= categories.count {
                        action = { commit(.right, url, into: categories[digit - 1]) }
                    }
                }
            }
        }

        guard let action else { return event }
        if !event.isARepeat { action() }   // garder une touche enfoncée ne trie pas 30 fichiers d'un coup
        return nil
    }

    // MARK: Boutons

    private func controls(for url: URL) -> some View {
        let suggested = target(for: url)
        let others = state.categories.filter { $0.isEnabled }

        return VStack(spacing: 14) {
            HStack(spacing: 9) {
                ActionPill(icon: "hand.raised.fill", title: "Garder", key: "←", color: .blue,
                           prominent: false, pressed: pressedKey == .left) { commit(.left, url) }
                    .help("Garder ici : ne plus me le proposer")
                ActionPill(icon: "trash.fill", title: "Corbeille", key: "↑", color: .red,
                           prominent: false, pressed: pressedKey == .up) { commit(.up, url) }
                    .help("Mettre à la corbeille (récupérable)")
                ActionPill(icon: suggested.symbol, title: "Ranger dans \(suggested.name)", key: "→",
                           color: tint(for: suggested), prominent: true,
                           pressed: pressedKey == .right) { commit(.right, url) }
                    .help("Ranger dans « \(suggested.folder) »")
            }
            .padding(LiquidGlass.isAvailable ? 0 : 6)
            .glassGroup(spacing: 10)
            .background {
                if !LiquidGlass.isAvailable {
                    Capsule().fill(.regularMaterial)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
                }
            }

            VStack(spacing: 8) {
                Text("OU RANGER DANS")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                // Toutes les catégories sur une ligne, à largeur égale (deux lignes équilibrées au-delà de 9) :
                // jamais de tuile isolée ni d'espace vide.
                let perRow = others.count <= 9 ? max(others.count, 1) : Int((Double(others.count) / 2).rounded(.up))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: perRow), spacing: 10) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, category in
                        Button {
                            commit(.right, url, into: category)
                        } label: {
                            CategoryTileLabel(category: category,
                                              number: index < 9 ? index + 1 : nil,
                                              color: CategoryTileLabel.color(for: index))
                        }
                        .buttonStyle(CategoryTileStyle(color: CategoryTileLabel.color(for: index),
                                                       isSuggested: category.id == suggested.id))
                        .help(index < 9 ? "\(category.name) — touche \(index + 1)" : category.name)
                    }
                }
                .frame(maxWidth: 960)
            }
        }
        .disabled(leaving != nil)
    }

    // MARK: Pile vide

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .hoverPop(scale: 1.12, angle: 12)
            Text("Tout est rangé !")
                .font(.title.weight(.semibold))
            Text("Les nouveaux fichiers de « \(state.watchedFolderName) » apparaîtront ici automatiquement.")
                .foregroundStyle(.secondary)
            Text("Pour trier un autre dossier, choisis-le en haut ou glisse-le ici depuis le Finder.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            HStack {
                Button("Choisir un dossier…") { state.chooseFolder() }
                Button("Ouvrir dans le Finder") { state.open(state.watchedFolderURL) }
                if state.keptCount > 0 {
                    Button("Revoir les \(state.keptCount) fichier\(state.keptCount > 1 ? "s" : "") gardé\(state.keptCount > 1 ? "s" : "")") {
                        state.resetKeptFiles()
                    }
                }
            }
            .padding(.top, 6)
        }
    }
}

/// Gros bouton rond façon Tinder.
struct RoundActionButton: View {
    let symbol: String
    let color: Color
    let title: String
    let key: String
    var diameter: CGFloat = 64
    var pressed = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.36, weight: .bold))
                    .foregroundStyle(pressed ? Color.white : color)
                    .frame(width: diameter, height: diameter)
                    .background(
                        Circle().fill(pressed ? AnyShapeStyle(color.gradient)
                                              : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
                    )
                    .overlay(Circle().strokeBorder(color.opacity(hovering ? 0.7 : 0.18), lineWidth: 1.5))
                    .shadow(color: color.opacity(hovering ? 0.30 : 0.12), radius: hovering ? 14 : 8, y: 4)
                    .scaleEffect(pressed ? 0.9 : (hovering ? 1.06 : 1))
                    .frame(width: 66, height: 66)   // même encombrement pour tous les boutons
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: pressed)

            HStack(spacing: 4) {
                KeyCap(key)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Une petite touche de clavier dessinée.
struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.18)))
    }
}

/// Rappel des touches, sous les boutons.
struct KeyLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            item(["1", "–", "9"], "catégorie")
            item(["espace"], "aperçu")
            item(["↩"], "ouvrir")
            item(["⌫"], "corbeille")
            item(["R"], "renommer")
            item(["N"], "nom proposé")
            item(["U"], "annuler")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassOr(Capsule()) {
            Capsule().fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
        }
    }

    private func item(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                if key == "–" { Text("–") } else { KeyCap(key) }
            }
            Text(label)
        }
        .hoverHighlight(cornerRadius: 6, inset: -3)
    }
}

/// Aperçu Quick Look en grand (touche Espace).
struct PreviewSheet: View {
    let url: URL
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                HStack(spacing: 4) {
                    KeyCap("espace")
                    Text("pour fermer · ← ↑ → pour trier")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Fermer", action: close)
            }
            .padding(12)
            Divider()
            if AppState.isFolder(url) {
                FolderContentsView(url: url)
            } else {
                QuickLookView(url: url)
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 560, idealHeight: 640)
    }
}

struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        guard let view = QLPreviewView(frame: .zero, style: .normal) else { return NSView() }
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? QLPreviewView)?.previewItem = url as NSURL
    }
}

/// Menu déroulant pour choisir le dossier à trier.
struct FolderPicker: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Menu {
            Section("Raccourcis") {
                ForEach(AppState.quickFolders) { folder in
                    Button {
                        state.selectFolder(folder.url)
                    } label: {
                        Label(folder.name, systemImage: folder.symbol)
                    }
                }
            }
            if !state.otherRecentFolders.isEmpty {
                Section("Récents") {
                    ForEach(state.otherRecentFolders, id: \.self) { url in
                        Button {
                            state.selectFolder(url)
                        } label: {
                            Label(FileManager.default.displayName(atPath: url.path), systemImage: "folder")
                        }
                    }
                    Button("Effacer les récents") { state.forgetRecentFolders() }
                }
            }
            Divider()
            Button("Choisir un dossier…  ⌘O") { state.chooseFolder() }
        } label: {
            Label(state.watchedFolderName, systemImage: "folder.fill")
                .font(.body.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .glassOr(Capsule(), interactive: true) {
            Capsule().fill(Color.primary.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        }
        .help("Dossier trié : \(state.watchedFolderDisplay)")
    }
}

/// Contenu d'une tuile de catégorie : grande icône, nom complet, touche.
struct CategoryTileLabel: View {
    let category: SortCategory
    let number: Int?
    let color: Color

    static let palette: [Color] = [.blue, .orange, .pink, .purple, .brown, .teal, .indigo, .mint, .red, .cyan]
    static func color(for index: Int) -> Color { palette[index % palette.count] }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: category.symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(color)
                .frame(height: 22)
            Text(category.name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let number {
                KeyCap("\(number)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
    }
}

/// Style des tuiles : fond teinté, survol, enfoncement, et tuile proposée mise en avant.
struct CategoryTileStyle: ButtonStyle {
    let color: Color
    let isSuggested: Bool

    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration, color: color, isSuggested: isSuggested)
    }

    private struct TileBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let isSuggested: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let highlight = isSuggested ? Color.green : color
            configuration.label
                .glassOr(RoundedRectangle(cornerRadius: 14, style: .continuous),
                         tint: highlight.opacity(isSuggested ? 0.30 : 0.12), interactive: true) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(highlight.opacity(configuration.isPressed ? 0.30 : (hovering ? 0.20 : 0.12)))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidGlass.isAvailable ? 14 : 12, style: .continuous)
                        .strokeBorder(highlight.opacity(isSuggested ? 0.9 : (LiquidGlass.isAvailable ? 0 : (hovering ? 0.6 : 0.25))),
                                      lineWidth: isSuggested ? 2 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSuggested {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color.green))
                            .offset(x: 5, y: -5)
                            .help("Catégorie proposée (→)")
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

/// Fond de l'écran de tri : uni, avec un halo violet discret derrière les cartes.
struct TriageBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.purple.opacity(0.10), Color.purple.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.42), startRadius: 10, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

/// Bouton d'action en pilule, sobre et lisible :
/// les actions secondaires sont neutres (seule l'icône est colorée),
/// l'action principale est pleine, à fort contraste (noir en clair, blanc en sombre).
struct ActionPill: View {
    let icon: String
    let title: String
    let key: String
    let color: Color
    let prominent: Bool
    var pressed = false
    let action: () -> Void

    @State private var hovering = false

    private var fill: Color { prominent ? Color.primary : Color.primary.opacity(hovering || pressed ? 0.09 : 0.055) }
    /// En Liquid Glass, le texte reste toujours sombre/clair selon le thème (verre lisible) ;
    /// sans verre, le bouton principal est plein et son texte inversé.
    private var ink: Color { prominent && !LiquidGlass.isAvailable ? Color(nsColor: .windowBackgroundColor) : Color.primary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(key)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(prominent && !LiquidGlass.isAvailable ? ink.opacity(0.16) : Color.primary.opacity(0.08))
                    )
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(height: 44)
            .glassOr(Capsule(), tint: prominent ? color.opacity(0.42) : nil, interactive: true) {
                Capsule().fill(fill)
                    .shadow(color: .black.opacity(prominent ? (hovering ? 0.22 : 0.15) : 0), radius: hovering ? 12 : 8, y: 4)
            }
            .scaleEffect(pressed ? 0.95 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
    }
}
