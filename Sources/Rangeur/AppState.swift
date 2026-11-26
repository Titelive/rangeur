import Foundation
import AppKit
import ServiceManagement

/// Une action de tri, gardée en mémoire pour ⌘Z.
enum TriageAction {
    case moved(UUID)        // fichier rangé ou mis à la corbeille (référence dans l'historique)
    case kept(String)       // fichier gardé dans le dossier (chemin)
}

@MainActor
final class AppState: ObservableObject {

    // MARK: Réglages persistés

    @Published var categories: [SortCategory] {
        didSet { persist(categories, Keys.categories); folderSuggestionCache.removeAll(); refreshQueue() }
    }
    @Published private(set) var history: [MoveRecord] {
        didSet { persist(history, Keys.history) }
    }
    /// Journal des décisions pour l'écran Statistiques.
    @Published private(set) var stats: [StatEvent] {
        didSet { Self.saveStats(stats) }
    }
    @Published var watchedFolderPath: String {
        didSet { defaults.set(watchedFolderPath, forKey: Keys.folder); restartWatching() }
    }
    @Published var autoMode: Bool {
        didSet { defaults.set(autoMode, forKey: Keys.auto); if autoMode { scheduleScan() } }
    }
    @Published var delaySeconds: Double {
        didSet { defaults.set(delaySeconds, forKey: Keys.delay) }
    }
    @Published var moveUnknown: Bool {
        didSet { defaults.set(moveUnknown, forKey: Keys.unknown) }
    }
    @Published var unknownFolderName: String {
        didSet { defaults.set(unknownFolderName, forKey: Keys.unknownName) }
    }
    @Published var notifyNewFiles: Bool {
        didSet { defaults.set(notifyNewFiles, forKey: Keys.notifyNew); if notifyNewFiles { askNotificationPermission() } }
    }
    @Published var notifyAutoSort: Bool {
        didSet { defaults.set(notifyAutoSort, forKey: Keys.notifyAuto); if notifyAutoSort { askNotificationPermission() } }
    }
    @Published var showDockBadge: Bool {
        didSet { defaults.set(showDockBadge, forKey: Keys.dockBadge); updateDockBadge() }
    }
    /// Les dossiers apparaissent aussi comme des cartes.
    @Published var includeFolders: Bool {
        didSet { defaults.set(includeFolders, forKey: Keys.includeFolders); refreshQueue() }
    }
    /// Renommage : proposer des noms plus clairs.
    @Published var renameEnabled: Bool {
        didSet { defaults.set(renameEnabled, forKey: Keys.renameEnabled); resetRenameSuggestions() }
    }
    /// Appliquer automatiquement le nom proposé quand on range le fichier.
    @Published var renameAutoApply: Bool {
        didSet { defaults.set(renameAutoApply, forKey: Keys.renameAuto) }
    }
    /// Lire le contenu (texte, PDF, texte des images) pour proposer un nom.
    @Published var renameReadContent: Bool {
        didSet { defaults.set(renameReadContent, forKey: Keys.renameContent); resetRenameSuggestions() }
    }
    /// Préfixer les noms proposés par la date (AAAA-MM-JJ).
    /// Date au début des noms proposés : jamais, factures et bulletins de paie, ou toujours.
    @Published var renameDateMode: RenameDateMode {
        didSet { defaults.set(renameDateMode.rawValue, forKey: Keys.renameDateMode); resetRenameSuggestions() }
    }
    /// Derniers dossiers triés (chemins), le plus récent en premier.
    @Published private(set) var recentFolders: [String] {
        didSet { defaults.set(recentFolders, forKey: Keys.recent) }
    }

    // MARK: État

    /// Fichiers en attente de tri (affichés comme des cartes).
    @Published private(set) var queue: [URL] = [] {
        didSet { updateDockBadge() }
    }
    /// Noms proposés pour les éléments de la pile.
    @Published private(set) var renameStates: [URL: RenameState] = [:]
    /// Demande d'ouverture du champ de renommage sur une carte (touche R).
    @Published var renameEditRequest: URL?
    /// Écran affiché dans la fenêtre (modifiable depuis une notification).
    @Published var selectedSection: SidebarItem? = .triage
    /// Incrémenté pour demander l'ouverture de la fenêtre principale.
    @Published private(set) var openWindowRequest = 0
    /// État de l'autorisation des notifications, pour les Réglages.
    @Published private(set) var notificationStatus: String = "…"
    @Published private(set) var isWatching = false
    @Published private(set) var lastResult: String?
    @Published private(set) var lastRun: Date?
    @Published private(set) var launchAtLogin = false
    @Published var errorMessage: String?
    @Published private(set) var undoStack: [TriageAction] = []
    @Published private(set) var sortedThisSession = 0

    /// Fichiers gardés d'un swipe à gauche : ils ne sont plus proposés.
    @Published private(set) var ignoredPaths: Set<String> {
        didSet { defaults.set(Array(ignoredPaths), forKey: Keys.ignored) }
    }
    /// Règles automatiques (« au bout de n jours, fais… »).
    @Published var autoRules: [AutoRule] {
        didSet { persist(autoRules, Keys.autoRules) }
    }
    @Published private(set) var lastRulesRun: Date?
    @Published private(set) var lastRulesResult: String?
    /// Exceptions écrites par l'utilisateur (motifs de noms).
    @Published var exceptions: [ExceptionRule] {
        didSet { persist(exceptions, Keys.exceptions); refreshQueue() }
    }

    private let defaults = UserDefaults.standard
    private let watcher = FolderWatcher()
    private var pendingScan: Task<Void, Never>?

    // Notifications
    private var knownQueue: Set<URL> = []
    private var queueSeeded = false
    private var pendingArrivals: [URL] = []
    private var arrivalsTask: Task<Void, Never>?
    private var autoBatches: [String: [UUID]] = [:]

    /// Catégorie proposée pour chaque dossier (chemin → id de catégorie, "" si aucune).
    private var folderSuggestionCache: [String: String] = [:]
    static let foldersFolderName = "Dossiers"
    static let renamedLabel = "Renommé"

    private enum Keys {
        static let categories = "categories"
        static let history = "history"
        static let folder = "watchedFolder"
        static let auto = "autoMode"
        static let delay = "delaySeconds"
        static let unknown = "moveUnknown"
        static let unknownName = "unknownFolderName"
        static let ignored = "ignoredPaths"
        static let recent = "recentFolders"
        static let notifyNew = "notifyNewFiles"
        static let notifyAuto = "notifyAutoSort"
        static let dockBadge = "showDockBadge"
        static let includeFolders = "includeFolders"
        static let renameEnabled = "renameEnabled"
        static let exceptions = "exceptions"
        static let autoRules = "autoRules"
        static let renameAuto = "renameAutoApply"
        static let renameContent = "renameReadContent"
        static let renameDate = "renameDatePrefix"
        static let renameDateMode = "renameDateMode"
    }

    /// Extensions des téléchargements en cours (Chrome, Safari, Firefox, Opera, qBittorrent…).
    static let partialExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp", "opdownload", "!qb", "aria2"
    ]
    static let historyLimit = 500

    static var defaultDownloadsPath: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
    }

    var watchedFolderURL: URL { URL(fileURLWithPath: watchedFolderPath, isDirectory: true) }
    var watchedFolderDisplay: String { (watchedFolderPath as NSString).abbreviatingWithTildeInPath }
    var watchedFolderName: String { FileManager.default.displayName(atPath: watchedFolderPath) }

    /// Dossiers proposés d'office dans le sélecteur.
    struct QuickFolder: Identifiable {
        let url: URL
        let symbol: String
        var id: String { url.path }
        var name: String { FileManager.default.displayName(atPath: url.path) }
    }

    static var quickFolders: [QuickFolder] {
        let fm = FileManager.default
        let list: [(FileManager.SearchPathDirectory, String)] = [
            (.downloadsDirectory, "arrow.down.circle"),
            (.desktopDirectory, "menubar.dock.rectangle"),
            (.documentDirectory, "doc"),
        ]
        return list.compactMap { directory, symbol in
            fm.urls(for: directory, in: .userDomainMask).first.map { QuickFolder(url: $0, symbol: symbol) }
        }
    }

    /// Dossiers récents encore présents sur le disque, hors raccourcis.
    var otherRecentFolders: [URL] {
        let quick = Set(Self.quickFolders.map(\.url.standardizedFileURL.path))
        return recentFolders
            .filter { !quick.contains($0) && FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // MARK: Init

    init() {
        let d = UserDefaults.standard
        _categories = Published(initialValue: Self.load([SortCategory].self, Keys.categories)
                                ?? SortCategory.makeDefaults())
        let loadedHistory = Self.load([MoveRecord].self, Keys.history) ?? []
        _history = Published(initialValue: loadedHistory)
        _stats = Published(initialValue: Self.loadStats() ?? Self.seedStats(from: loadedHistory))
        _watchedFolderPath = Published(initialValue: d.string(forKey: Keys.folder) ?? Self.defaultDownloadsPath)
        _autoMode = Published(initialValue: d.object(forKey: Keys.auto) as? Bool ?? false)
        _delaySeconds = Published(initialValue: d.object(forKey: Keys.delay) as? Double ?? 5)
        _moveUnknown = Published(initialValue: d.object(forKey: Keys.unknown) as? Bool ?? false)
        _unknownFolderName = Published(initialValue: d.string(forKey: Keys.unknownName) ?? "Divers")
        _recentFolders = Published(initialValue: d.stringArray(forKey: Keys.recent) ?? [])
        _notifyNewFiles = Published(initialValue: d.object(forKey: Keys.notifyNew) as? Bool ?? true)
        _notifyAutoSort = Published(initialValue: d.object(forKey: Keys.notifyAuto) as? Bool ?? true)
        _showDockBadge = Published(initialValue: d.object(forKey: Keys.dockBadge) as? Bool ?? true)
        _includeFolders = Published(initialValue: d.object(forKey: Keys.includeFolders) as? Bool ?? true)
        _renameEnabled = Published(initialValue: d.object(forKey: Keys.renameEnabled) as? Bool ?? true)
        _renameAutoApply = Published(initialValue: d.object(forKey: Keys.renameAuto) as? Bool ?? false)
        _renameReadContent = Published(initialValue: d.object(forKey: Keys.renameContent) as? Bool ?? true)
        _renameDateMode = Published(initialValue: RenameDateMode(rawValue: d.string(forKey: Keys.renameDateMode) ?? "")
                                    ?? ((d.object(forKey: Keys.renameDate) as? Bool) == true ? .always : .smart))
        _ignoredPaths = Published(initialValue: Set(d.stringArray(forKey: Keys.ignored) ?? []))
        _exceptions = Published(initialValue: Self.load([ExceptionRule].self, Keys.exceptions) ?? [])
        _autoRules = Published(initialValue: Self.load([AutoRule].self, Keys.autoRules) ?? [])
        launchAtLogin = SMAppService.mainApp.status == .enabled

        watcher.onChange = { [weak self] in
            Task { @MainActor in self?.scheduleScan() }
        }
        setUpNotifications()
        restartWatching()
        startRulesTimer()
    }

    // MARK: Surveillance

    func restartWatching() {
        watcher.stop()
        isWatching = watcher.start(url: watchedFolderURL)
        if !isWatching {
            errorMessage = "Impossible de surveiller « \(watchedFolderDisplay) ». Vérifie que le dossier existe et que Rangeur a le droit d'y accéder."
        }
        scheduleScan(after: 0.1)
    }

    /// Regroupe les événements rapprochés puis rafraîchit la pile (et range si le mode auto est actif).
    func scheduleScan(after seconds: Double = 1.0) {
        pendingScan?.cancel()
        pendingScan = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if self.autoMode { self.organize(manual: false) }
            // Les règles « tout de suite » n'attendent pas l'heure suivante.
            if self.autoRules.contains(where: { $0.enabled && $0.days == 0 }) { self.runRules(manual: false) }
            self.refreshQueue()
        }
    }

    // MARK: Analyse du dossier

    private struct Candidate {
        let url: URL
        let isPackage: Bool
        var waited: TimeInterval = 0   // depuis l'arrivée dans le dossier
        let isFolder: Bool
        let age: TimeInterval
    }

    /// Noms des dossiers créés par Rangeur (catégories), jamais proposés au tri.
    private var reservedFolderNames: Set<String> {
        var names = Set(categories.compactMap { $0.folder.split(separator: "/").first.map { String($0).lowercased() } })
        names.insert(unknownFolderName.lowercased())
        names.insert(Self.foldersFolderName.lowercased())
        return names
    }

    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
    }

    /// Liste les fichiers du dossier surveillé qui peuvent être triés.
    private func candidates() -> [Candidate] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .addedToDirectoryDateKey]
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(at: watchedFolderURL,
                                               includingPropertiesForKeys: keys,
                                               options: [.skipsHiddenFiles])
        } catch {
            errorMessage = "Impossible de lire « \(watchedFolderDisplay) » : \(error.localizedDescription)"
            return []
        }

        let now = Date()
        let reserved = reservedFolderNames
        var result: [(Candidate, Date)] = []
        for url in items {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = values.isDirectory ?? false
            let isPackage = values.isPackage ?? false
            let isFolder = isDir && !isPackage
            if isFolder && (!includeFolders || reserved.contains(url.lastPathComponent.lowercased())) { continue }
            if Self.partialExtensions.contains(url.pathExtension.lowercased()) { continue }
            if ignoredPaths.contains(url.path) { continue }
            if isExcepted(url, from: .ignore) { continue }
            let modified = values.contentModificationDate ?? .distantPast
            let added = values.addedToDirectoryDate ?? modified
            result.append((Candidate(url: url, isPackage: isPackage, waited: now.timeIntervalSince(added), isFolder: isFolder, age: now.timeIntervalSince(modified)), added))
        }
        // Les plus récents d'abord, comme dans le Finder.
        return result.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Met à jour la pile de cartes « À trier ».
    func refreshQueue() {
        let fresh = candidates()
            .filter { $0.age >= 1.5 }   // évite d'afficher un fichier encore en train d'être écrit
            .map(\.url)
        if fresh != queue { queue = fresh }

        // Nouveaux fichiers depuis le dernier passage → notification.
        if queueSeeded {
            let arrivals = fresh.filter { !knownQueue.contains($0) }
            if !arrivals.isEmpty { notifyArrivals(arrivals) }
        }
        knownQueue = knownQueue.union(fresh).filter { FileManager.default.fileExists(atPath: $0.path) }
        queueSeeded = true

        // Oublie les propositions des fichiers partis, et prépare celles des prochaines cartes.
        let inQueue = Set(fresh)
        renameStates = renameStates.filter { inQueue.contains($0.key) }
        prefetchRenameSuggestions()

        // Oublie les fichiers ignorés qui n'existent plus.
        let existing = ignoredPaths.filter { FileManager.default.fileExists(atPath: $0) }
        if existing.count != ignoredPaths.count { ignoredPaths = existing }
    }

    func suggestion(for url: URL) -> SortCategory? {
        if Self.isFolder(url) { return folderSuggestion(for: url) }
        return categories.first { $0.matches(url.pathExtension) }
    }

    /// Catégorie où ira l'élément avec un swipe à droite.
    func target(for url: URL) -> SortCategory {
        if let category = suggestion(for: url) { return category }
        if Self.isFolder(url) {
            return SortCategory(name: Self.foldersFolderName, symbol: "folder", extensions: [])
        }
        return SortCategory(name: unknownFolderName, symbol: "questionmark.folder", extensions: [])
    }

    /// Pour un dossier : la catégorie qui représente au moins 60 % de ses fichiers (ex. un dossier de photos → Images).
    private func folderSuggestion(for url: URL) -> SortCategory? {
        if let cached = folderSuggestionCache[url.path] {
            return cached.isEmpty ? nil : categories.first { $0.id.uuidString == cached }
        }
        var counts: [UUID: Int] = [:]
        var total = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                           options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let file as URL in enumerator {
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                total += 1
                if let category = categories.first(where: { $0.matches(file.pathExtension) }) {
                    counts[category.id, default: 0] += 1
                }
                if total >= 400 { break }
            }
        }
        var result: SortCategory?
        if total > 0, let best = counts.max(by: { $0.value < $1.value }), Double(best.value) / Double(total) >= 0.6 {
            result = categories.first { $0.id == best.key }
        }
        folderSuggestionCache[url.path] = result?.id.uuidString ?? ""
        return result
    }

    // MARK: Tri façon Tinder

    /// Swipe à droite (ou choix d'une catégorie) : range le fichier.
    func sort(_ url: URL, into category: SortCategory) {
        var newName: String?
        if renameAutoApply, !isExcepted(url, from: .noRename),
           case .suggested(let name, _) = renameStates[url] { newName = name }
        guard let record = move(url, toFolder: category.folder, label: category.name, symbol: category.symbol,
                                newName: newName) else { return }
        logStat(id: record.id, action: .sorted, category: category.name, symbol: category.symbol,
                url: url, measureAt: record.movedURL)
        undoStack.append(.moved(record.id))
        sortedThisSession += 1
        refreshQueue()
    }

    /// Swipe à gauche : garde le fichier où il est (il ne sera plus proposé).
    func keep(_ url: URL) {
        logStat(action: .kept, category: "Gardé", symbol: "hand.raised", url: url, measureAt: url)
        ignoredPaths.insert(url.path)
        undoStack.append(.kept(url.path))
        refreshQueue()
    }

    /// Swipe vers le haut : met le fichier à la corbeille (récupérable depuis la Corbeille ou avec ⌘Z).
    func trash(_ url: URL) {
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            let record = MoveRecord(date: Date(), fileName: url.lastPathComponent,
                                    originalURL: url, movedURL: (resulting as URL?) ?? url,
                                    categoryName: "Corbeille", symbol: "trash")
            addToHistory([record])
            logStat(id: record.id, action: .trashed, category: "Corbeille", symbol: "trash",
                    url: url, measureAt: record.movedURL)
            undoStack.append(.moved(record.id))
            sortedThisSession += 1
            refreshQueue()
        } catch {
            errorMessage = "« \(url.lastPathComponent) » n'a pas pu être mis à la corbeille : \(error.localizedDescription)"
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// ⌘Z : annule la dernière action de tri.
    func undoLast() {
        guard let action = undoStack.popLast() else { return }
        switch action {
        case .kept(let path):
            ignoredPaths.remove(path)
            if let index = stats.lastIndex(where: { $0.action == .kept && $0.sourcePath == path }) {
                stats.remove(at: index)
            }
        case .moved(let id):
            if let record = history.first(where: { $0.id == id }) {
                restore(record, ignoreAfterwards: false)
                if record.categoryName != Self.renamedLabel {
                    sortedThisSession = max(0, sortedThisSession - 1)
                }
            }
        }
        refreshQueue()
    }

    // MARK: Rangement automatique

    /// Délais proposés (en secondes).
    static let delayPresets: [(TimeInterval, String)] = [
        (5, "Tout de suite"), (60, "1 minute"), (300, "5 minutes"), (900, "15 minutes"), (3600, "1 heure"),
        (6 * 3600, "6 heures"), (86_400, "1 jour"), (3 * 86_400, "3 jours"), (7 * 86_400, "1 semaine"),
    ]

    static func delayLabel(_ seconds: TimeInterval) -> String {
        if let p = delayPresets.first(where: { $0.0 == seconds }) { return p.1 }
        if seconds < 60 { return "\(Int(seconds)) s" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h" }
        return "\(Int(seconds / 86_400)) j"
    }

    /// Quand ce fichier sera rangé automatiquement (nil si le mode auto est éteint ou s'il ne le sera pas).
    func autoSortDate(for url: URL) -> Date? {
        guard autoMode, !Self.isFolder(url), !isExcepted(url, from: .ignore) else { return nil }
        guard suggestion(for: url) != nil || moveUnknown else { return nil }
        let added = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? Date()
        return added.addingTimeInterval(delaySeconds)
    }

    /// Range d'un coup tous les fichiers reconnus selon leur type.
    func organize(manual: Bool) {
        var moved = 0
        var soonestRetry: Double?
        let stable = manual ? 1.5 : 5.0          // jamais un fichier modifié il y a moins de 5 s
        let delay = manual ? 0 : delaySeconds     // délai choisi, compté depuis l'arrivée du fichier

        var movedRecords: [MoveRecord] = []
        for candidate in candidates() {
            if candidate.isFolder { continue }   // les dossiers se trient uniquement à la main
            let target: (folder: String, label: String, symbol: String)
            if let category = suggestion(for: candidate.url) {
                target = (category.folder, category.name, category.symbol)
            } else if moveUnknown && !candidate.isPackage {
                target = (unknownFolderName, unknownFolderName, "questionmark.folder")
            } else {
                continue
            }
            let remaining = max(stable - candidate.age, delay - candidate.waited)
            if remaining > 0 {
                soonestRetry = min(soonestRetry ?? remaining, remaining)
                continue
            }
            if let record = move(candidate.url, toFolder: target.folder, label: target.label, symbol: target.symbol) {
                logStat(id: record.id, action: .auto, category: target.label, symbol: target.symbol,
                        url: candidate.url, measureAt: record.movedURL)
                moved += 1
                movedRecords.append(record)
            }
        }

        if manual || moved > 0 {
            lastRun = Date()
            lastResult = moved == 0 ? "Rien à ranger" : "\(moved) fichier\(moved > 1 ? "s" : "") rangé\(moved > 1 ? "s" : "")"
        }
        if !manual && !movedRecords.isEmpty { notifyAutoSorted(movedRecords) }
        if let retry = soonestRetry, autoMode {
            scheduleScan(after: retry + 0.5)
        }
        if manual { refreshQueue() }
    }

    // MARK: Déplacements

    @discardableResult
    private func move(_ url: URL, toFolder folderName: String, label: String, symbol: String,
                      newName: String? = nil) -> MoveRecord? {
        let folder = folderName.trimmingCharacters(in: .whitespaces)
        guard !folder.isEmpty else { return nil }
        let fm = FileManager.default
        let destinationDir = watchedFolderURL.appendingPathComponent(folder, isDirectory: true)
        do {
            try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            let destination = Self.uniqueURL(for: newName ?? url.lastPathComponent, in: destinationDir)
            try fm.moveItem(at: url, to: destination)
            let record = MoveRecord(date: Date(), fileName: url.lastPathComponent,
                                    originalURL: url, movedURL: destination,
                                    categoryName: label, symbol: symbol)
            addToHistory([record])
            errorMessage = nil
            return record
        } catch {
            errorMessage = "« \(url.lastPathComponent) » n'a pas pu être déplacé : \(error.localizedDescription)"
            return nil
        }
    }

    private func addToHistory(_ records: [MoveRecord]) {
        history = Array((records.reversed() + history).prefix(Self.historyLimit))
    }

    /// Remet un fichier à son emplacement d'origine.
    func undo(_ record: MoveRecord) {
        restore(record, ignoreAfterwards: true)
        undoStack.removeAll { if case .moved(let id) = $0 { return id == record.id } else { return false } }
        refreshQueue()
    }

    private func restore(_ record: MoveRecord, ignoreAfterwards: Bool) {
        guard let index = history.firstIndex(where: { $0.id == record.id }), !history[index].undone else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: record.movedURL.path) else {
            errorMessage = "« \(record.fileName) » n'est plus à l'endroit où Rangeur l'avait mis."
            return
        }
        let back = Self.uniqueURL(for: record.originalURL.lastPathComponent,
                                  in: record.originalURL.deletingLastPathComponent())
        do {
            try fm.moveItem(at: record.movedURL, to: back)
            history[index].undone = true
            history[index].restoredURL = back
            stats.removeAll { $0.id == record.id }
            // Sinon le mode automatique le rangerait aussitôt de nouveau.
            if ignoreAfterwards || autoMode { ignoredPaths.insert(back.path) }
        } catch {
            errorMessage = "Impossible de remettre « \(record.fileName) » en place : \(error.localizedDescription)"
        }
    }

    static func uniqueURL(for name: String, in directory: URL) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            index += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    // MARK: Catégories

    func addCategory() {
        categories.append(SortCategory(name: "Nouvelle catégorie", symbol: "folder", extensions: []))
    }

    func removeCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
    }

    func resetCategories() {
        categories = SortCategory.makeDefaults()
    }

    func resetKeptFiles() {
        ignoredPaths.removeAll()
        undoStack.removeAll { if case .kept = $0 { return true } else { return false } }
        refreshQueue()
    }

    var keptCount: Int { ignoredPaths.count }

    // MARK: Divers

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = watchedFolderURL
        panel.message = "Choisis le dossier dont tu veux trier les fichiers"
        panel.prompt = "Trier ce dossier"
        if panel.runModal() == .OK, let url = panel.url {
            selectFolder(url)
        }
    }

    /// Change le dossier à trier : la pile de cartes se recharge avec son contenu.
    func selectFolder(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            errorMessage = "« \(url.lastPathComponent) » n'est pas un dossier."
            return
        }
        let path = url.standardizedFileURL.path
        recentFolders = Array(([path] + recentFolders.filter { $0 != path }).prefix(8))
        guard path != watchedFolderPath else { return }
        errorMessage = nil
        queue = []
        knownQueue = []
        queueSeeded = false   // pas de notification pour le contenu déjà présent du nouveau dossier
        watchedFolderPath = path   // relance la surveillance et recharge la pile
    }

    func forgetRecentFolders() {
        recentFolders = [watchedFolderPath]
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func clearHistory() {
        history.removeAll()
        undoStack.removeAll { if case .moved = $0 { return true } else { return false } }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Ouverture au démarrage impossible : \(error.localizedDescription). Lance Rangeur.app (créée par build.sh) plutôt que depuis Xcode."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Renommage

    var renameAIStatus: String { RenameEngine.aiStatusDescription }
    var renameUsesAI: Bool { RenameEngine.aiAvailable }

    /// Analyse automatiquement les noms peu clairs des 3 prochaines cartes.
    private func prefetchRenameSuggestions() {
        guard renameEnabled else { return }
        for url in queue.prefix(3) where renameStates[url] == nil && RenameEngine.needsRename(url, dateMode: renameDateMode)
                                      && !isExcepted(url, from: .noRename) {
            requestRenameSuggestion(for: url, force: false)
        }
    }

    /// Demande une proposition de nom (touche I, ou automatiquement pour les noms peu clairs).
    func requestRenameSuggestion(for url: URL, force: Bool = true) {
        if renameStates[url] == .analyzing { return }
        renameStates[url] = .analyzing
        let options = RenameOptions(readContent: renameReadContent, dateMode: renameDateMode)
        Task { [weak self] in
            let result = await RenameEngine.suggest(for: url, options: options, force: force)
            guard let self, self.renameStates[url] == .analyzing else { return }
            self.renameStates[url] = result
        }
    }

    func dismissRenameSuggestion(for url: URL) {
        renameStates[url] = .fine
    }

    func applyRenameSuggestion(for url: URL) {
        guard case .suggested(let name, _) = renameStates[url] else { return }
        rename(url, to: name)
    }

    /// Renomme un élément sur place. Annulable avec ⌘Z ou depuis l'Activité.
    @discardableResult
    func rename(_ url: URL, to proposedName: String) -> URL? {
        let ext = url.pathExtension
        var base = proposedName
        if !ext.isEmpty, base.lowercased().hasSuffix("." + ext.lowercased()) {
            base = String(base.dropLast(ext.count + 1))
        }
        guard let cleanBase = RenameEngine.clean(base) else {
            errorMessage = "Ce nom n'est pas valide."
            return nil
        }
        let newName = ext.isEmpty ? cleanBase : "\(cleanBase).\(ext)"
        guard newName != url.lastPathComponent else {
            renameStates[url] = .fine
            return url
        }
        let directory = url.deletingLastPathComponent()
        // Un simple changement de majuscules doit pouvoir se faire même si macOS considère les deux noms identiques.
        let caseOnly = newName.lowercased() == url.lastPathComponent.lowercased()
        let destination = caseOnly ? directory.appendingPathComponent(newName) : Self.uniqueURL(for: newName, in: directory)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            errorMessage = "« \(url.lastPathComponent) » n'a pas pu être renommé : \(error.localizedDescription)"
            return nil
        }
        let record = MoveRecord(date: Date(), fileName: url.lastPathComponent,
                                originalURL: url, movedURL: destination,
                                categoryName: Self.renamedLabel, symbol: "pencil")
        addToHistory([record])
        undoStack.append(.moved(record.id))
        if ignoredPaths.remove(url.path) != nil { ignoredPaths.insert(destination.path) }
        renameStates[url] = nil
        renameStates[destination] = .fine
        errorMessage = nil
        refreshQueue()
        return destination
    }

    private func resetRenameSuggestions() {
        renameStates = renameStates.filter { $0.value == .analyzing }
        prefetchRenameSuggestions()
    }

    // MARK: Règles automatiques

    private var rulesTimer: Timer?

    /// Les règles s'appliquent peu après le lancement, puis toutes les heures.
    private func startRulesTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.runRules(manual: false) }
        rulesTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runRules(manual: false)
                if self?.autoMode == true { self?.scheduleScan(after: 0.1) }   // délais longs (heures, jours)
            }
        }
    }

    func addRule(_ rule: AutoRule = AutoRule()) { autoRules.append(rule) }
    func removeRule(_ id: UUID) { autoRules.removeAll { $0.id == id } }

    /// Modèles proposés dans le menu « Modèles », regroupés par thème.
    func ruleTemplates() -> [(section: String, items: [(String, AutoRule)])] {
        func cat(_ name: String) -> AutoRule.Target {
            categories.first { $0.name == name }.map { .category($0.id) } ?? .pattern(name)
        }
        return [
            ("Installeurs", [
                ("Installeurs → corbeille tout de suite", AutoRule(target: cat("Installeurs"), days: 0, action: .trash)),
                ("Installeurs de plus d'1 jour → corbeille", AutoRule(target: cat("Installeurs"), days: 1, action: .trash)),
                ("Installeurs de plus de 7 jours → corbeille", AutoRule(target: cat("Installeurs"), days: 7, action: .trash)),
            ]),
            ("Archives", [
                ("Archives déjà décompressées → corbeille tout de suite", AutoRule(target: cat("Archives"), days: 0, action: .trash, extra: .extracted)),
                ("Archives de plus d'1 jour → corbeille", AutoRule(target: cat("Archives"), days: 1, action: .trash)),
                ("Archives non ouvertes depuis 30 jours → corbeille", AutoRule(target: cat("Archives"), basis: .lastOpened, days: 30, action: .trash)),
            ]),
            ("Ménage malin ✨", [
                ("Doublons exacts → corbeille tout de suite", AutoRule(target: .any, days: 0, action: .trash, extra: .duplicate)),
                ("Fichiers vides (0 octet) → corbeille", AutoRule(target: .any, days: 0, action: .trash, extra: .empty)),
                ("Téléchargements abandonnés depuis 2 jours → corbeille", AutoRule(target: .partial, days: 2, action: .trash)),
                ("Captures d'écran de plus de 7 jours → dossier « Captures »", AutoRule(target: .pattern("Capture d'écran*"), days: 7, action: .moveTo, folder: "Captures")),
                ("Invitations (.ics) de plus d'1 jour → corbeille", AutoRule(target: .pattern(".ics"), days: 1, action: .trash)),
                ("Torrents (.torrent) → corbeille tout de suite", AutoRule(target: .pattern(".torrent"), days: 0, action: .trash)),
                ("Fichiers de plus de 1 Go non ouverts depuis 30 jours → dossier « Gros fichiers »", AutoRule(target: .any, basis: .lastOpened, days: 30, action: .moveTo, folder: "Gros fichiers", extra: .big)),
            ]),
            ("Rangement", [
                ("Tout fichier de plus de 3 jours → le ranger", AutoRule(target: .any, days: 3, action: .sort)),
                ("Tout fichier non ouvert depuis 6 mois → dossier « Archives »", AutoRule(target: .any, basis: .lastOpened, days: 180, action: .moveTo, folder: "Archives")),
                ("Fichiers gardés depuis 90 jours → me les reproposer", AutoRule(target: .kept, days: 90, action: .unkeep)),
            ]),
        ]
    }

    private static let lastUsedKey = kMDItemLastUsedDate as String

    private func date(of url: URL, basis: AutoRule.Basis) -> Date? {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        let added = values?.addedToDirectoryDate ?? values?.creationDate
        guard basis == .lastOpened else { return added }
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return used
        }
        return added   // jamais ouvert : on compte depuis son arrivée
    }

    private func files(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return items.filter { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let folder = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
            return !folder && !Self.partialExtensions.contains(url.pathExtension.lowercased())
        }
    }

    /// Les fichiers concernés par une règle, en ce moment.
    func ruleMatches(_ rule: AutoRule) -> [URL] {
        guard rule.days >= 0 else { return [] }
        let root = watchedFolderURL
        var pool: [URL] = []
        switch rule.target {
        case .kept:
            pool = ignoredPaths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        case .category(let id):
            pool = files(in: root)
            if rule.action != .sort, let c = categories.first(where: { $0.id == id }) {
                pool += files(in: root.appendingPathComponent(c.folder, isDirectory: true))
            }
        case .partial:
            let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                      options: [.skipsHiddenFiles])) ?? []
            pool = items.filter { Self.partialExtensions.contains($0.pathExtension.lowercased()) }
        case .any, .pattern:
            pool = files(in: root)
            if rule.action != .sort {
                // les fichiers déjà rangés comptent aussi (sauf pour « ranger »)
                for folder in Set(categories.map(\.folder) + [unknownFolderName]) {
                    pool += files(in: root.appendingPathComponent(folder, isDirectory: true))
                }
            }
        }
        let limit = Date().addingTimeInterval(-Double(rule.days) * 86_400)
        return pool.filter { url in
            let atRoot = url.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path
            if rule.target != .kept && ignoredPaths.contains(url.path) { return false }   // gardé = intouchable
            if isExcepted(url, from: .ignore) { return false }
            switch rule.target {
            case .any, .kept, .partial: break
            case .pattern(let p):
                if !ExceptionRule(pattern: p).matches(url.lastPathComponent) { return false }
            case .category(let id):
                guard let c = categories.first(where: { $0.id == id }) else { return false }
                let inFolder = url.deletingLastPathComponent().lastPathComponent == c.folder
                if !(c.matches(url.pathExtension) && atRoot) && !inFolder { return false }
            }
            if rule.action == .sort && (!atRoot || suggestion(for: url) == nil) { return false }
            if rule.action == .moveTo && url.deletingLastPathComponent().lastPathComponent == rule.folder { return false }
            // Jamais un fichier modifié il y a moins d'une minute (téléchargement qui se termine, fichier en cours d'écriture).
            if let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               Date().timeIntervalSince(m) < 60 { return false }
            guard let d = date(of: url, basis: rule.basis), d <= limit else { return false }
            return passesExtra(rule.extra, url)
        }
    }

    private func passesExtra(_ extra: AutoRule.Extra, _ url: URL) -> Bool {
        let fm = FileManager.default
        switch extra {
        case .none:
            return true
        case .empty:
            return ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 1) == 0
        case .big:
            return ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) >= 1_000_000_000
        case .extracted:
            // « projet.zip » à côté d'un dossier « projet » (ou « projet 2 ») : l'archive a déjà été ouverte.
            let base = url.deletingPathExtension().deletingPathExtension().lastPathComponent   // gère .tar.gz
            let dir = url.deletingLastPathComponent()
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            return names.contains { name in
                var isDir: ObjCBool = false
                let lower = name.lowercased(), b = base.lowercased()
                guard lower == b || lower.hasPrefix(b + " "),
                      fm.fileExists(atPath: dir.appendingPathComponent(name).path, isDirectory: &isDir) else { return false }
                return isDir.boolValue
            }
        case .duplicate:
            // Même taille et même contenu qu'un autre fichier du dossier, qui est plus ancien : on garde l'original.
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 else { return false }
            let mine = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantFuture
            for other in files(in: url.deletingLastPathComponent()) where other != url {
                let v = try? other.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                guard v?.fileSize == size else { continue }
                let theirs = v?.creationDate ?? .distantFuture
                guard theirs < mine || (theirs == mine && other.lastPathComponent < url.lastPathComponent) else { continue }
                if fm.contentsEqual(atPath: url.path, andPath: other.path) { return true }
            }
            return false
        }
    }

    /// Applique les règles actives. `manual` : bouton « Appliquer maintenant ».
    func runRules(manual: Bool) {
        var done = 0
        var handled = Set<String>()
        var records: [MoveRecord] = []
        for rule in autoRules where rule.enabled {
            for url in ruleMatches(rule) where !handled.contains(url.path) {
                handled.insert(url.path)
                switch rule.action {
                case .trash:
                    var resulting: NSURL?
                    if (try? FileManager.default.trashItem(at: url, resultingItemURL: &resulting)) != nil {
                        let r = MoveRecord(date: Date(), fileName: url.lastPathComponent, originalURL: url,
                                           movedURL: (resulting as URL?) ?? url, categoryName: "Corbeille (règle)", symbol: "trash")
                        addToHistory([r]); records.append(r)
                        logStat(id: r.id, action: .trashed, category: "Corbeille", symbol: "trash", url: url, measureAt: r.movedURL)
                        done += 1
                    }
                case .sort:
                    if let c = suggestion(for: url),
                       let r = move(url, toFolder: c.folder, label: c.name, symbol: c.symbol) {
                        records.append(r)
                        logStat(id: r.id, action: .auto, category: c.name, symbol: c.symbol, url: url, measureAt: r.movedURL)
                        done += 1
                    }
                case .moveTo:
                    if let r = move(url, toFolder: rule.folder, label: rule.folder, symbol: "folder") {
                        records.append(r)
                        logStat(id: r.id, action: .auto, category: rule.folder, symbol: "folder", url: url, measureAt: r.movedURL)
                        done += 1
                    }
                case .unkeep:
                    if ignoredPaths.remove(url.path) != nil { done += 1 }
                }
            }
        }
        lastRulesRun = Date()
        if done > 0 || manual {
            lastRulesResult = done == 0 ? "Aucun fichier concerné" : "\(done) fichier\(done > 1 ? "s" : "") traité\(done > 1 ? "s" : "") par les règles"
        }
        if !records.isEmpty && !manual { notifyAutoSorted(records) }
        if done > 0 { refreshQueue() }
    }

    func ruleSummary(_ rule: AutoRule) -> String {
        let target: String
        switch rule.target {
        case .any: target = "un fichier"
        case .kept: target = "un fichier gardé"
        case .partial: target = "un téléchargement abandonné"
        case .pattern(let p): target = "« \(p) »"
        case .category(let id): target = categories.first { $0.id == id }?.name ?? "une catégorie supprimée"
        }
        return "\(target) · \(rule.days) j · \(rule.action.label)"
    }

    // MARK: Exceptions

    /// `.ignore` : jamais proposé. `.noRename` : jamais renommé automatiquement (les deux types d'exception comptent).
    func isExcepted(_ url: URL, from scope: ExceptionRule.Scope) -> Bool {
        let name = url.lastPathComponent
        return exceptions.contains { rule in
            (scope == .ignore ? rule.scope == .ignore : true) && rule.matches(name)
        }
    }

    func addException(_ pattern: String = "", scope: ExceptionRule.Scope = .ignore) {
        exceptions.append(ExceptionRule(pattern: pattern, scope: scope))
    }

    func removeException(_ id: UUID) {
        exceptions.removeAll { $0.id == id }
    }

    /// Fichiers gardés, du plus récent nom au plus ancien, avec leur chemin.
    var keptItems: [URL] {
        ignoredPaths.sorted { ($0 as NSString).lastPathComponent.localizedStandardCompare(($1 as NSString).lastPathComponent) == .orderedAscending }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Reproposer un fichier gardé.
    func unkeep(_ url: URL) {
        ignoredPaths.remove(url.path)
        refreshQueue()
    }

    /// Nombre d'éléments du dossier trié concernés par une exception.
    func matchCount(for rule: ExceptionRule) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: watchedFolderPath)) ?? []
        return names.filter { !$0.hasPrefix(".") && rule.matches($0) }.count
    }

    // MARK: Statistiques

    private func logStat(id: UUID = UUID(), action: StatEvent.Action, category: String, symbol: String,
                         url: URL, measureAt: URL) {
        let folder = Self.isFolder(measureAt)
        let size = folder ? 0 : Int64((try? measureAt.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        stats.append(StatEvent(id: id, date: Date(), action: action, category: category, symbol: symbol,
                               bytes: size, fileName: url.lastPathComponent, sourcePath: url.path,
                               isFolder: folder))
        if folder {
            // La taille d'un dossier se calcule en arrière-plan.
            Task.detached(priority: .utility) { [weak self] in
                let total = FolderSummary.compute(measureAt).totalSize
                await self?.setStatBytes(id, total)
            }
        }
    }

    private func setStatBytes(_ id: UUID, _ bytes: Int64) {
        if let index = stats.firstIndex(where: { $0.id == id }) { stats[index].bytes = bytes }
    }

    func resetStats() {
        stats = []
    }

    private static var statsFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Rangeur", isDirectory: true).appendingPathComponent("stats.json")
    }

    private static func loadStats() -> [StatEvent]? {
        guard let data = try? Data(contentsOf: statsFileURL) else { return nil }
        return try? JSONDecoder().decode([StatEvent].self, from: data)
    }

    private static func saveStats(_ events: [StatEvent]) {
        let url = statsFileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Premier lancement avec les stats : on reprend l'historique existant.
    private static func seedStats(from history: [MoveRecord]) -> [StatEvent] {
        history.filter { !$0.undone && $0.categoryName != renamedLabel }.map { record in
            let size = (try? record.movedURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let trashed = record.categoryName == "Corbeille"
            return StatEvent(id: record.id, date: record.date, action: trashed ? .trashed : .sorted,
                             category: record.categoryName, symbol: record.symbol, bytes: Int64(size),
                             fileName: record.fileName, sourcePath: record.originalURL.path,
                             isFolder: false)
        }
    }

    // MARK: Notifications et pastille du Dock

    private func setUpNotifications() {
        let notifier = Notifier.shared
        notifier.setup()
        notifier.onOpen = { [weak self] toActivity in
            Task { @MainActor in self?.showMainWindow(section: toActivity ? .activity : .triage) }
        }
        notifier.onUndoBatch = { [weak self] batchID in
            Task { @MainActor in self?.undoBatch(batchID) }
        }
        if notifyNewFiles || notifyAutoSort { askNotificationPermission() } else { refreshNotificationStatus() }
    }

    func askNotificationPermission() {
        Notifier.shared.requestAuthorization { [weak self] _ in
            Task { @MainActor in self?.refreshNotificationStatus() }
        }
    }

    func refreshNotificationStatus() {
        guard Notifier.shared.isAvailable else {
            notificationStatus = "Indisponibles depuis Xcode : lance Rangeur.app (build.sh)."
            return
        }
        Notifier.shared.status { [weak self] status in
            Task { @MainActor in
                switch status {
                case .authorized, .provisional: self?.notificationStatus = "Autorisées"
                case .denied: self?.notificationStatus = "Refusées dans Réglages Système"
                case .notDetermined: self?.notificationStatus = "Pas encore autorisées"
                default: self?.notificationStatus = "Indisponibles"
                }
            }
        }
    }

    var notificationsDenied: Bool { notificationStatus.hasPrefix("Refusées") }

    func showMainWindow(section: SidebarItem? = nil) {
        if let section { selectedSection = section }
        openWindowRequest += 1
        NSApp.activate(ignoringOtherApps: true)
    }

    /// L'utilisateur regarde déjà Rangeur : inutile de le notifier.
    private var userIsLooking: Bool {
        NSApp.isActive && NSApp.windows.contains { $0.isVisible && $0.isKeyWindow && !($0 is NSPanel) }
    }

    private func notifyArrivals(_ arrivals: [URL]) {
        guard notifyNewFiles else { return }
        pendingArrivals.append(contentsOf: arrivals)
        // Regroupe les fichiers qui arrivent ensemble (ex. plusieurs téléchargements) en une seule notification.
        arrivalsTask?.cancel()
        arrivalsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            let stillWaiting = self.pendingArrivals.filter { self.queue.contains($0) }
            self.pendingArrivals.removeAll()
            guard !stillWaiting.isEmpty, !self.userIsLooking else { return }

            let names = stillWaiting.map(\.lastPathComponent)
            let title = stillWaiting.count == 1
                ? "Nouveau fichier à trier"
                : "\(stillWaiting.count) nouveaux fichiers à trier"
            var body = names.prefix(3).joined(separator: ", ")
            if names.count > 3 { body += " et \(names.count - 3) autre\(names.count - 3 > 1 ? "s" : "")" }
            let waiting = self.queue.count
            Notifier.shared.post(
                id: "new-files",
                title: title,
                subtitle: "Dans \(self.watchedFolderName) · \(waiting) en attente",
                body: body,
                category: Notifier.Category.newFiles)
        }
    }

    private func notifyAutoSorted(_ records: [MoveRecord]) {
        guard notifyAutoSort, !userIsLooking else { return }
        let batchID = UUID().uuidString
        autoBatches[batchID] = records.map(\.id)
        let title = records.count == 1
            ? "1 fichier rangé automatiquement"
            : "\(records.count) fichiers rangés automatiquement"
        let body = records.prefix(3).map { "\($0.fileName) → \($0.categoryName)" }.joined(separator: "\n")
            + (records.count > 3 ? "\n…et \(records.count - 3) autre\(records.count - 3 > 1 ? "s" : "")" : "")
        Notifier.shared.post(id: "auto-\(batchID)", title: title, body: body,
                             category: Notifier.Category.autoSorted,
                             userInfo: ["batch": batchID], sound: false)
    }

    private func undoBatch(_ batchID: String) {
        guard let ids = autoBatches.removeValue(forKey: batchID) else { return }
        for id in ids {
            if let record = history.first(where: { $0.id == id }) { undo(record) }
        }
    }

    func sendTestNotification() {
        askNotificationPermission()
        Notifier.shared.post(id: "test", title: "Rangeur", subtitle: "Notification de test",
                             body: "Les notifications fonctionnent. Bon tri !",
                             category: Notifier.Category.newFiles)
    }

    private func updateDockBadge() {
        let count = queue.count
        NSApp?.dockTile.badgeLabel = (showDockBadge && count > 0) ? "\(count)" : nil
    }

    // MARK: Persistance

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
