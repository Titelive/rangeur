import Foundation

/// Une catégorie de rangement : les fichiers dont l'extension figure dans `extensions`
/// sont déplacés dans le sous-dossier `folder` du dossier surveillé.
struct SortCategory: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var folder: String
    var symbol: String
    var extensions: [String]
    var isEnabled: Bool

    init(id: UUID = UUID(),
         name: String,
         folder: String? = nil,
         symbol: String,
         extensions: [String],
         isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.folder = folder ?? name
        self.symbol = symbol
        self.extensions = extensions
        self.isEnabled = isEnabled
    }

    func matches(_ ext: String) -> Bool {
        isEnabled && !ext.isEmpty && extensions.contains(ext.lowercased())
    }

    /// Transforme « .JPG, png ; heic » en ["jpg", "png", "heic"].
    static func parseExtensions(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Catégories proposées au premier lancement (identifiants neufs à chaque appel).
    static func makeDefaults() -> [SortCategory] {
        [
            SortCategory(name: "Images", symbol: "photo",
                         extensions: ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "avif",
                                      "tif", "tiff", "bmp", "svg", "ico", "psd", "raw", "dng",
                                      "cr2", "cr3", "nef", "arw"]),
            SortCategory(name: "Documents", symbol: "doc.text",
                         extensions: ["pdf", "doc", "docx", "odt", "rtf", "txt", "md", "pages",
                                      "xls", "xlsx", "ods", "csv", "numbers",
                                      "ppt", "pptx", "odp", "key", "epub"]),
            SortCategory(name: "Vidéos", symbol: "film",
                         extensions: ["mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv",
                                      "mpg", "mpeg"]),
            SortCategory(name: "Musique", symbol: "music.note",
                         extensions: ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aif",
                                      "aiff"]),
            SortCategory(name: "Archives", symbol: "archivebox",
                         extensions: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]),
            SortCategory(name: "Installeurs", symbol: "shippingbox",
                         extensions: ["dmg", "pkg", "mpkg", "iso", "app"]),
            SortCategory(name: "Code", symbol: "curlybraces",
                         extensions: ["swift", "py", "js", "ts", "json", "html", "css", "xml",
                                      "yml", "yaml", "sh", "rb", "go", "java", "c", "cpp", "h",
                                      "ipynb"]),
        ]
    }
}

/// Un déplacement effectué par Rangeur, conservé dans l'historique pour pouvoir l'annuler.
struct MoveRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var fileName: String
    var originalURL: URL
    var movedURL: URL
    var categoryName: String
    var symbol: String
    var undone: Bool = false
    var restoredURL: URL?

    /// Emplacement actuel du fichier.
    var currentURL: URL { undone ? (restoredURL ?? originalURL) : movedURL }
}

/// Une décision de tri, conservée pour les statistiques (indépendamment de l'historique).
struct StatEvent: Identifiable, Codable, Hashable {
    enum Action: String, Codable, CaseIterable {
        case sorted, auto, kept, trashed

        var label: String {
            switch self {
            case .sorted: return "Rangé"
            case .auto: return "Rangé auto"
            case .kept: return "Gardé"
            case .trashed: return "Corbeille"
            }
        }
    }

    var id: UUID
    var date: Date
    var action: Action
    var category: String
    var symbol: String
    var bytes: Int64
    var fileName: String
    var sourcePath: String
    var isFolder: Bool
}

/// Une exception : les fichiers dont le nom correspond ne sont jamais proposés, ou jamais renommés.
struct ExceptionRule: Identifiable, Codable, Hashable {
    enum Scope: String, Codable, CaseIterable, Identifiable {
        case ignore, noRename
        var id: Self { self }
        var label: String {
            switch self {
            case .ignore: return "Ne jamais proposer"
            case .noRename: return "Ne jamais renommer"
            }
        }
    }

    var id = UUID()
    var pattern: String
    var scope: Scope = .ignore

    /// « .dmg » = extension ; sinon motif avec * et ? (« Facture* », « *devis* »), sans tenir compte des majuscules.
    func matches(_ fileName: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return false }
        if p.hasPrefix("."), !p.contains("*"), !p.contains("?") {
            return fileName.lowercased().hasSuffix(p.lowercased())
        }
        let glob = (p.contains("*") || p.contains("?")) ? p : "*\(p)*"
        return NSPredicate(format: "SELF LIKE[c] %@", glob).evaluate(with: fileName)
    }
}

/// Une règle automatique : « quand un fichier [cible] est là depuis [n] jours, alors [action] ».
struct AutoRule: Identifiable, Codable, Hashable {
    enum Target: Codable, Hashable {
        case any                    // n'importe quel fichier
        case category(UUID)         // un type (Images, Installeurs…), y compris déjà rangé dans son dossier
        case pattern(String)        // un motif de nom (.dmg, Facture*, *devis*)
        case kept                   // les fichiers gardés d'un swipe à gauche
        case partial                // téléchargements abandonnés (.crdownload, .part…)
    }
    /// Conditions en plus, pour des règles plus malines.
    enum Extra: String, Codable, CaseIterable, Identifiable {
        case none, extracted, duplicate, empty, big
        var id: Self { self }
        var label: String {
            switch self {
            case .none: return "sans autre condition"
            case .extracted: return "et déjà décompressé (dossier du même nom à côté)"
            case .duplicate: return "et en double (même contenu qu'un autre fichier)"
            case .empty: return "et vide (0 octet)"
            case .big: return "et de plus de 1 Go"
            }
        }
    }
    enum Basis: String, Codable, CaseIterable, Identifiable {
        case added, lastOpened
        var id: Self { self }
        var label: String { self == .added ? "est là depuis plus de" : "n'a pas été ouvert depuis" }
    }
    enum Action: String, Codable, CaseIterable, Identifiable {
        case trash, sort, moveTo, unkeep
        var id: Self { self }
        var label: String {
            switch self {
            case .trash: return "le mettre à la corbeille"
            case .sort: return "le ranger dans sa catégorie"
            case .moveTo: return "le déplacer dans le dossier"
            case .unkeep: return "me le reproposer"
            }
        }
        var symbol: String {
            switch self {
            case .trash: return "trash"
            case .sort: return "tray.and.arrow.down"
            case .moveTo: return "folder"
            case .unkeep: return "arrow.uturn.backward"
            }
        }
    }

    var id = UUID()
    var enabled = false
    var target: Target = .any
    var basis: Basis = .added
    var days = 30
    var action: Action = .trash
    var folder = "Archives"
    var extra: Extra = .none

    init(enabled: Bool = false, target: Target = .any, basis: Basis = .added, days: Int = 30,
         action: Action = .trash, folder: String = "Archives", extra: Extra = .none) {
        self.enabled = enabled; self.target = target; self.basis = basis; self.days = days
        self.action = action; self.folder = folder; self.extra = extra
    }

    // Lecture tolérante : une ancienne règle sans les nouveaux champs reste valide.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        target = try c.decodeIfPresent(Target.self, forKey: .target) ?? .any
        basis = try c.decodeIfPresent(Basis.self, forKey: .basis) ?? .added
        days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 30
        action = try c.decodeIfPresent(Action.self, forKey: .action) ?? .trash
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? "Archives"
        extra = try c.decodeIfPresent(Extra.self, forKey: .extra) ?? .none
    }
}
