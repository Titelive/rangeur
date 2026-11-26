import Foundation
import AppKit
import PDFKit
import Vision
import ImageIO
import CoreServices
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Résultat d'une analyse de nom.
enum RenameState: Equatable {
    case analyzing
    case suggested(name: String, byAI: Bool)   // nom complet, extension comprise
    case fine                                  // le nom actuel convient (rien à afficher)
    case noSuggestion(String)                  // analysé, mais pas de meilleur nom : on explique pourquoi
}

/// Où mettre la date au début des noms proposés.
enum RenameDateMode: String, CaseIterable, Identifiable {
    case never, smart, always
    var id: Self { self }
    var label: String {
        switch self {
        case .never: return "Jamais"
        case .smart: return "Factures et bulletins de paie"
        case .always: return "Toujours"
        }
    }
}

struct RenameOptions {
    var readContent = true
    var dateMode: RenameDateMode = .smart
}

/// Factures (date du jour de facturation) et bulletins de paie (mois de la période).
enum DatedDocument {
    enum Kind { case invoice, payslip, other }

    static let payslipWords = ["bulletin de paie", "bulletin de salaire", "fiche de paie", "fiche de salaire", "payslip",
                               "pay slip", "salaire de base", "cotisations salariales", "net à payer avant impôt",
                               "net a payer avant impot", "net imposable"]
    static let invoiceWords = ["facture", "invoice", "reçu", "recu de paiement", "receipt", "quittance", "avis d'échéance",
                               "avis d’échéance", "devis", "avoir n", "note d'honoraires", "ticket de caisse", "relevé de compte",
                               "order confirmation", "confirmation de commande"]
    /// Mots repérés dans un simple nom de fichier.
    static let nameWords = ["facture", "invoice", "bulletin", "paie", "salaire", "payslip", "recu", "reçu", "receipt",
                            "quittance", "devis", "echeance", "échéance"]

    static func kind(_ info: FileFacts) -> Kind {
        let head = ([info.fileName, info.documentTitle ?? ""] + info.textLines.prefix(80)).joined(separator: "\n").lowercased()
        if payslipWords.contains(where: { head.contains($0) }) { return .payslip }
        if invoiceWords.contains(where: { head.contains($0) }) { return .invoice }
        return .other
    }

    private static let months: [String: Int] = [
        "janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7,
        "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12,
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12,
        "janv": 1, "févr": 2, "fevr": 2, "sept": 9, "oct": 10, "nov": 11, "déc": 12, "dec": 12,
    ]
    private static var monthAlternation: String {
        months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    }

    struct Found { let date: Date; let monthOnly: Bool }

    /// Toutes les dates d'une ligne, dans l'ordre.
    static func dates(in line: String) -> [Found] {
        let cal = Calendar(identifier: .gregorian)
        let thisYear = cal.component(.year, from: Date())
        func make(_ y: Int, _ m: Int, _ d: Int, monthOnly: Bool = false) -> Found? {
            guard (2000...thisYear + 1).contains(y), (1...12).contains(m), (1...31).contains(d),
                  let date = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
            return Found(date: date, monthOnly: monthOnly)
        }
        var out: [(Int, Found)] = []
        let ns = line as NSString
        func each(_ pattern: String, _ build: ([String]) -> Found?) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
                if let f = build(groups) { out.append((m.range.location, f)) }
            }
        }
        each(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#) { g in make(Int(g[1])!, Int(g[2])!, Int(g[3])!) }
        each(#"\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})\b"#) { g in make(Int(g[3])!, Int(g[2])!, Int(g[1])!) }
        each(#"\b(\d{1,2})(?:er)?\s+("# + monthAlternation + #")\.?\s+(\d{4})\b"#) { g in
            make(Int(g[3])!, months[g[2].lowercased()] ?? 0, Int(g[1])!)
        }
        each(#"(?<!\d\s)(?<!\d)\b("# + monthAlternation + #")\.?\s+(\d{4})\b"#) { g in
            make(Int(g[2])!, months[g[1].lowercased()] ?? 0, 1, monthOnly: true)
        }
        each(#"\b(\d{1,2})/(\d{4})\b"#) { g in make(Int(g[2])!, Int(g[1])!, 1, monthOnly: true) }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    /// Date de la facture : de préférence sur une ligne qui parle de date, sinon la première date du document.
    static func invoiceDate(_ info: FileFacts) -> Date? {
        let lines = Array(info.textLines.prefix(80))
        let keys = ["date de facture", "date de facturation", "date d'émission", "date d’émission", "invoice date",
                    "date de la facture", "facture du", "émise le", "emise le", "date :", "date:", "le "]
        for (i, line) in lines.enumerated() where keys.contains(where: { line.lowercased().contains($0) }) {
            if let f = dates(in: line).first(where: { !$0.monthOnly }) { return f.date }
            if i + 1 < lines.count, let f = dates(in: lines[i + 1]).first(where: { !$0.monthOnly }) { return f.date }
        }
        for line in lines { if let f = dates(in: line).first(where: { !$0.monthOnly }) { return f.date } }
        for line in [info.fileName] { if let f = dates(in: line).first { return f.date } }
        return nil
    }

    /// Mois du bulletin : la période de paie, sinon « octobre 2026 », sinon le mois le plus cité.
    static func payslipMonth(_ info: FileFacts) -> Date? {
        let lines = Array(info.textLines.prefix(80)) + [info.fileName]
        for line in lines where ["période", "periode", "period", "mois de", "paie du", "du "].contains(where: { line.lowercased().contains($0) }) {
            if let f = dates(in: line).first { return f.date }
        }
        for line in lines { if let f = dates(in: line).first(where: \.monthOnly) { return f.date } }
        var counts: [String: (Date, Int)] = [:]
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        for line in lines { for f in dates(in: line) { let k = fmt.string(from: f.date); counts[k] = ((counts[k]?.0 ?? f.date), (counts[k]?.1 ?? 0) + 1) } }
        return counts.values.max { $0.1 < $1.1 }?.0
    }

    /// Retire d'un nom les dates déjà écrites (« octobre 2026 », « 28/10/2026 », « 2026-10 »…), pour ne pas les doubler.
    static func stripDates(_ name: String) -> String {
        var s = name
        let patterns = [#"\b\d{4}-\d{1,2}(-\d{1,2})?\b"#, #"\b\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}\b"#,
                        #"\b(\d{1,2}(er)?\s+)?("# + monthAlternation + #")\.?\s+\d{4}\b"#, #"\b\d{1,2}/\d{4}\b"#]
        for p in patterns { s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive]) }
        s = s.replacingOccurrences(of: #"\s+(du|de|d')\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " -_.,"))
    }
}

/// Propose des noms de fichiers plus clairs.
/// Utilise Apple Intelligence (sur l'appareil) quand elle est disponible, sinon des règles simples.
enum RenameEngine {

    // MARK: Disponibilité de l'IA

    static var aiAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var aiStatusDescription: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Apple Intelligence est active : l'analyse se fait sur ton Mac, rien ne sort."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence est désactivée. Active-la dans Réglages Système → Apple Intelligence et Siri pour de meilleures propositions."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence se prépare (téléchargement du modèle). En attendant, Rangeur utilise des règles simples."
            case .unavailable(.deviceNotEligible):
                return "Ce Mac n'est pas compatible Apple Intelligence : Rangeur utilise des règles simples (titre du PDF, date de la photo…)."
            case .unavailable:
                return "Apple Intelligence n'est pas disponible : Rangeur utilise des règles simples."
            }
        }
        return "Apple Intelligence demande macOS 26 : Rangeur utilise des règles simples (titre du PDF, date de la photo…)."
        #else
        return "Compilé sans le SDK macOS 26 (Xcode 26) : Rangeur utilise des règles simples. Mets Xcode à jour pour profiter d'Apple Intelligence."
        #endif
    }

    // MARK: Le nom a-t-il besoin d'être changé ?

    private static let genericPrefixes = [
        "img", "dsc", "dscn", "dcim", "pxl", "mvimg", "vid", "mov", "screenshot", "screen shot",
        "capture d’écran", "capture d'écran", "capture", "image", "photo", "scan", "document", "doc",
        "download", "downloads", "file", "fichier", "untitled", "sans titre", "unnamed", "unknown",
        "téléchargement", "telechargement", "export", "output", "attachment", "pièce jointe", "piece jointe",
        "whatsapp image", "whatsapp video", "signal-", "telegram", "new document", "nouveau document",
    ]

    /// Repère les noms peu parlants : identifiants aléatoires, « IMG_1234 », « document (3) »…
    static func needsRename(_ url: URL, dateMode: RenameDateMode = .never) -> Bool {
        let base = url.deletingPathExtension().lastPathComponent
        let lower = base.lowercased().trimmingCharacters(in: .whitespaces)
        // Une facture ou un bulletin sans date au début : on propose de l'ajouter.
        if dateMode != .never, DatedDocument.nameWords.contains(where: { lower.contains($0) }),
           lower.range(of: #"^\d{4}-\d{2}"#, options: .regularExpression) == nil { return true }
        if lower.count <= 3 { return true }

        let letters = base.filter(\.isLetter).count
        let digits = base.filter(\.isNumber).count

        // UUID ou suite hexadécimale (6BDA7570-20C0-4A51-…)
        if base.range(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-"#, options: .regularExpression) != nil { return true }
        if base.range(of: #"^[0-9A-Fa-f]{16,}$"#, options: .regularExpression) != nil { return true }
        // Surtout des chiffres (470351766_1713282919246346_…_n)
        if digits >= 8 && letters <= 3 { return true }
        // Préfixes génériques (IMG_6071, Capture d'écran…, document)
        for prefix in genericPrefixes where lower.hasPrefix(prefix) {
            let rest = lower.dropFirst(prefix.count).filter(\.isLetter)
            if rest.count <= 3 || lower.contains(where: \.isNumber) { return true }
        }
        // Doublons « (1) », « copie »
        if lower.range(of: #"\(\d+\)$"#, options: .regularExpression) != nil { return true }
        if lower.hasSuffix(" copie") || lower.hasSuffix(" copy") { return true }
        // Noms encodés (Mon%20fichier) ou en_snake_case_tres_long
        if base.contains("%20") || (base.contains("+") && !base.contains(" ")) { return true }
        if base.filter({ $0 == "_" }).count >= 3 && !base.contains(" ") { return true }
        return false
    }

    // MARK: Proposition

    /// `force` : demande explicite (touche I) ; l'IA doit alors toujours proposer un nom.
    static func suggest(for url: URL, options: RenameOptions, force: Bool = false) async -> RenameState {
        let info = await Task.detached(priority: .userInitiated) {
            FileFacts.gather(url, readContent: options.readContent)
        }.value

        var base: String?
        var byAI = false
        var aiNote: String?
        let kind = options.readContent || options.dateMode != .never ? DatedDocument.kind(info) : .other
        let dated = options.dateMode == .always || (options.dateMode == .smart && kind != .other)
        let currentBase = url.deletingPathExtension().lastPathComponent

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), aiAvailable {
            switch await askAppleIntelligence(info, force: force, kind: kind, dateAdded: dated) {
            case .name(let text): base = text; byAI = true
            case .keep:
                // Nom clair, mais une facture ou un bulletin gagne quand même sa date.
                if dated { base = currentBase } else {
                    return .noSuggestion("Apple Intelligence trouve le nom actuel déjà clair. Appuie sur I pour lui demander quand même une idée.")
                }
            case .failed(let reason): aiNote = "Apple Intelligence n'a pas pu répondre (\(reason))."
            }
        }
        #endif

        if base == nil { base = heuristicName(info) }
        if base == nil, dated, kind != .other { base = currentBase }
        guard var name = base.flatMap(clean), !name.isEmpty else {
            let why = aiNote ?? (aiAvailable ? "" : shortAIStatus)
            return .noSuggestion(("Pas de meilleur nom trouvé" + (options.readContent ? "" : " (lecture du contenu désactivée)") + ". " + why).trimmingCharacters(in: .whitespaces))
        }

        if dated {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            var date: Date?
            switch kind {
            case .payslip:
                fmt.dateFormat = "yyyy-MM"                      // bulletin de paie : le mois
                date = DatedDocument.payslipMonth(info) ?? info.bestDate
            case .invoice:
                fmt.dateFormat = "yyyy-MM-dd"                   // facture : le jour de facturation
                date = DatedDocument.invoiceDate(info) ?? info.bestDate
            case .other:
                fmt.dateFormat = "yyyy-MM-dd"
                date = info.bestDate
            }
            if let date {
                let stripped = DatedDocument.stripDates(name)
                name = "\(fmt.string(from: date)) \(stripped.isEmpty ? name : stripped)"
            }
        }
        let ext = url.pathExtension
        let full = ext.isEmpty ? name : "\(name).\(ext)"
        if full.compare(url.lastPathComponent, options: [.caseInsensitive]) == .orderedSame {
            return .noSuggestion("Le nom proposé est identique au nom actuel.")
        }
        return .suggested(name: full, byAI: byAI)
    }

    /// Pourquoi l'IA n'est pas utilisée, en une phrase courte (affichée sur la carte).
    static var shortAIStatus: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            case .unavailable(.appleIntelligenceNotEnabled): return "Sans IA : Apple Intelligence est désactivée dans Réglages Système."
            case .unavailable(.modelNotReady): return "Sans IA : le modèle d'Apple Intelligence se télécharge encore."
            case .unavailable(.deviceNotEligible): return "Sans IA : ce Mac n'est pas compatible Apple Intelligence."
            case .unavailable: return "Sans IA : Apple Intelligence est indisponible."
            }
        }
        return "Sans IA : il faut macOS 26."
        #else
        return "Sans IA : l'app a été compilée sans le SDK macOS 26 (Xcode 26)."
        #endif
    }

    static let keepMarker = "GARDER"

    enum AIAnswer { case name(String), keep, failed(String) }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func askAppleIntelligence(_ info: FileFacts, force: Bool, kind: DatedDocument.Kind, dateAdded: Bool) async -> AIAnswer {
        let instructions = """
        Tu renommes des fichiers téléchargés sur un Mac pour qu'on les retrouve facilement.
        Propose un nom court (2 à 7 mots), précis et lisible, qui dit ce qu'est le fichier : \
        type de document, organisme ou personne, sujet, mois ou année si utile.
        Écris dans la langue du contenu (en français par défaut), avec des espaces et des majuscules normales.
        N'ajoute pas d'extension et n'utilise pas les caractères / : \\ * ? " < > |.
        N'invente rien : appuie-toi seulement sur les informations fournies.
        """ + (kind == .invoice ? "\nC'est une facture ou un reçu : commence par « Facture » (ou « Reçu », « Devis »…) puis l'entreprise ou l'organisme, et le sujet si utile." : "")
          + (kind == .payslip ? "\nC'est un bulletin de paie : écris « Bulletin de paie » suivi du nom de l'employeur." : "")
          + (dateAdded ? "\nN'écris aucune date dans le nom : elle sera ajoutée automatiquement." : "")
          + (force
            ? "\nPropose toujours un nom, même si le nom actuel est correct."
            : "\nSi le nom actuel est déjà clair et descriptif, réponds exactement \(keepMarker).") + """

        Réponds uniquement avec le nom, sans guillemets ni explication.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: info.promptDescription,
                                                     options: GenerationOptions(temperature: 0.2))
            let text = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
            if text.uppercased().hasPrefix(keepMarker) { return force ? .failed("réponse vide") : .keep }
            return text.isEmpty ? .failed("réponse vide") : .name(text)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
    #endif

    /// Sans IA : titre du PDF, première ligne d'un texte, date de la photo, site d'origine…
    private static func heuristicName(_ info: FileFacts) -> String? {
        if let title = info.documentTitle, isMeaningful(title) { return title }
        if let line = info.textLines.first(where: isMeaningful) {
            return String(line.prefix(60))
        }
        let dateText = info.bestDate.map { $0.formatted(.iso8601.year().month().day()) }
        let kind: String
        switch info.kind {
        case .screenshot: kind = "Capture d'écran"
        case .photo: kind = "Photo"
        case .image: kind = "Image"
        case .video: kind = "Vidéo"
        case .pdf, .text: kind = "Document"
        case .folder: kind = "Dossier"
        case .other: kind = "Fichier"
        }
        var parts = [kind]
        if let host = info.sourceHost { parts.append(host) }
        if let dateText { parts.append(dateText) }
        return parts.count > 1 ? parts.joined(separator: " ") : nil
    }

    private static func isMeaningful(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        let letters = t.filter(\.isLetter).count
        let lower = t.lowercased()
        return letters >= 4 && t.count <= 90
            && !["untitled", "sans titre", "microsoft word", "document", "page 1"].contains(where: { lower.hasPrefix($0) })
    }

    /// Nettoie une proposition pour en faire un nom de fichier valide.
    static func clean(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'«»“”‘’`*"))
        // Retire une extension éventuellement ajoutée par l'IA.
        if let dot = name.lastIndex(of: "."), name.distance(from: dot, to: name.endIndex) <= 6,
           name[name.index(after: dot)...].allSatisfy({ $0.isLetter || $0.isNumber }) {
            name = String(name[..<dot])
        }
        let forbidden = CharacterSet(charactersIn: "/:\\*?\"<>|\n\r\t")
        name = name.components(separatedBy: forbidden).joined(separator: "-")
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        if name.count > 80 { name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return name.isEmpty ? nil : name
    }
}

// MARK: - Informations sur le fichier

/// Ce que Rangeur sait d'un fichier pour lui trouver un nom.
struct FileFacts {
    enum Kind { case pdf, text, photo, screenshot, image, video, folder, other }

    var fileName: String
    var kind: Kind
    var typeDescription: String
    var size: Int64
    var bestDate: Date?
    var sourceHost: String?
    var sourceURL: String?
    var documentTitle: String?
    var textLines: [String] = []
    var folderItems: [String] = []

    var promptDescription: String {
        var lines = ["Nom actuel : \(fileName)", "Type : \(typeDescription)"]
        if size > 0 { lines.append("Taille : \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))") }
        if let bestDate { lines.append("Date : \(bestDate.formatted(date: .long, time: .omitted))") }
        if let sourceURL { lines.append("Téléchargé depuis : \(sourceURL)") }
        if let documentTitle { lines.append("Titre interne : \(documentTitle)") }
        if !folderItems.isEmpty {
            lines.append("Contenu du dossier : \(folderItems.prefix(25).joined(separator: ", "))")
        }
        if !textLines.isEmpty {
            var excerpt = ""
            for line in textLines where excerpt.count < 1500 { excerpt += line + "\n" }
            lines.append("Extrait du contenu :\n\(excerpt)")
        }
        return lines.joined(separator: "\n")
    }

    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "xml", "html", "htm", "rtf", "log", "yml", "yaml",
        "swift", "py", "js", "ts", "css", "sh", "rb", "go", "java", "c", "cpp", "h", "ics", "vcf", "srt",
    ]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff", "bmp", "gif", "avif"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]

    static func gather(_ url: URL, readContent: Bool) -> FileFacts {
        let ext = url.pathExtension.lowercased()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .localizedTypeDescriptionKey,
                                                       .isDirectoryKey, .isPackageKey])
        let isFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)

        var facts = FileFacts(fileName: url.lastPathComponent, kind: .other,
                              typeDescription: values?.localizedTypeDescription ?? (ext.isEmpty ? "Fichier" : ext.uppercased()),
                              size: Int64(values?.fileSize ?? 0),
                              bestDate: values?.creationDate)

        // Site d'origine (métadonnée « Provenance » enregistrée par le navigateur).
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let sources = MDItemCopyAttribute(item, kMDItemWhereFroms) as? [String] {
            let page = sources.count > 1 ? sources[1] : sources.first
            facts.sourceURL = page.map { String($0.prefix(200)) }
            facts.sourceHost = page.flatMap { URL(string: $0)?.host }?
                .replacingOccurrences(of: "www.", with: "")
        }

        if isFolder {
            facts.kind = .folder
            facts.typeDescription = "Dossier"
            let items = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            facts.folderItems = items.filter { !$0.hasPrefix(".") }.sorted()
            return facts
        }

        if ext == "pdf" {
            facts.kind = .pdf
            if let pdf = PDFDocument(url: url) {
                if let title = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
                    facts.documentTitle = title
                }
                if readContent {
                    var text = ""
                    for index in 0..<min(pdf.pageCount, 2) {
                        text += (pdf.page(at: index)?.string ?? "") + "\n"
                    }
                    facts.textLines = Self.lines(text)
                }
            }
        } else if textExtensions.contains(ext) {
            facts.kind = .text
            if readContent, let handle = try? FileHandle(forReadingFrom: url) {
                let data = (try? handle.read(upToCount: 6000)) ?? Data()
                try? handle.close()
                facts.textLines = Self.lines(String(decoding: data, as: UTF8.self))
            }
        } else if imageExtensions.contains(ext) {
            let lower = facts.fileName.lowercased()
            facts.kind = (lower.contains("capture") || lower.contains("screenshot") || lower.contains("screen shot"))
                ? .screenshot : .image
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                   let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                    if let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                        if let date = formatter.date(from: original) {
                            facts.bestDate = date
                            if facts.kind == .image { facts.kind = .photo }
                        }
                    }
                    if facts.kind == .image, let comment = exif[kCGImagePropertyExifUserComment] as? String,
                       comment.lowercased().contains("screenshot") {
                        facts.kind = .screenshot
                    }
                }
                if readContent && facts.kind != .photo {
                    facts.textLines = Self.recognizeText(in: source)
                }
            }
        } else if videoExtensions.contains(ext) {
            facts.kind = .video
        }
        return facts
    }

    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(60)
            .map { String($0.prefix(200)) }
    }

    /// Texte présent dans une image (capture d'écran, scan, facture photographiée…).
    private static func recognizeText(in source: CGImageSource) -> [String] {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1800,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR", "en-US"]
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return []
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { $0.filter(\.isLetter).count >= 3 }
            .prefix(40)
            .map { $0 }
    }
}
