import SwiftUI
import Charts

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "7 jours"
    case month = "30 jours"
    case year = "12 mois"
    case all = "Tout"

    var id: Self { self }

    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        case .all: return nil
        }
    }
}

/// L'écran Statistiques.
struct StatsView: View {
    @EnvironmentObject var state: AppState
    @State private var period: StatsPeriod = .month
    @State private var confirmReset = false

    private let calendar = Calendar.current

    // MARK: Données

    private var periodStart: Date? {
        guard let days = period.days else { return nil }
        return calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date()))
    }

    private var events: [StatEvent] {
        guard let start = periodStart else { return state.stats }
        return state.stats.filter { $0.date >= start }
    }

    private func count(_ actions: StatEvent.Action..., in list: [StatEvent]) -> Int {
        list.filter { actions.contains($0.action) }.count
    }

    private func bytes(_ actions: StatEvent.Action..., in list: [StatEvent]) -> Int64 {
        list.filter { actions.contains($0.action) }.reduce(0) { $0 + $1.bytes }
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    // MARK: Vue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Période", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 380)

                if events.isEmpty {
                    emptyState
                } else {
                    let list = events
                    tiles(list)
                    activityCard(list)
                    HStack(alignment: .top, spacing: 16) {
                        categoryCard(list)
                        swipeCard(list)
                    }
                    funFacts(list)
                }
            }
            .padding(24)
        }
        .navigationTitle("Statistiques")
        .toolbar {
            ToolbarItem {
                Button("Réinitialiser…") { confirmReset = true }
                    .disabled(state.stats.isEmpty)
            }
        }
        .confirmationDialog("Remettre les statistiques à zéro ?", isPresented: $confirmReset) {
            Button("Remettre à zéro", role: .destructive) { state.resetStats() }
        } message: {
            Text("Tes fichiers ne sont pas touchés : seuls les chiffres sont effacés.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(state.stats.isEmpty ? "Pas encore de statistiques" : "Rien sur cette période")
                .font(.title3.weight(.semibold))
            Text("Trie quelques fichiers dans « À trier » et reviens ici.")
                .foregroundStyle(.secondary)
            Button("Aller trier") { state.selectedSection = .triage }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: Tuiles

    private func tiles(_ list: [StatEvent]) -> some View {
        let total = list.count
        let sorted = count(.sorted, .auto, in: list)
        let trashed = count(.trashed, in: list)
        let activeDays = Set(list.map { calendar.startOfDay(for: $0.date) }).count
        let streak = Self.streaks(state.stats, calendar: calendar)

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            StatTile(symbol: "hand.draw.fill", color: .accentColor,
                     value: "\(total)", title: "Décisions",
                     detail: activeDays > 0 ? "≈ \(Int((Double(total) / Double(activeDays)).rounded())) par jour actif" : nil)
            StatTile(symbol: "checkmark.circle.fill", color: .green,
                     value: "\(sorted)", title: "Rangés",
                     detail: "\(formatBytes(bytes(.sorted, .auto, in: list))) mis en ordre")
            StatTile(symbol: "trash.fill", color: .red,
                     value: "\(trashed)", title: "À la corbeille",
                     detail: "\(formatBytes(bytes(.trashed, in: list))) libérés")
            StatTile(symbol: "flame.fill", color: .orange,
                     value: "\(streak.current) j", title: "Série en cours",
                     detail: "Record : \(streak.best) jour\(streak.best > 1 ? "s" : "") d'affilée")
        }
    }

    // MARK: Activité

    private struct Bucket: Identifiable {
        let date: Date
        let action: StatEvent.Action
        let count: Int
        var id: String { "\(date.timeIntervalSince1970)-\(action.rawValue)" }
    }

    private struct BucketKey: Hashable {
        let date: Date
        let action: StatEvent.Action
    }

    private func unit(for list: [StatEvent]) -> Calendar.Component {
        switch period {
        case .week, .month: return .day
        case .year: return .month
        case .all:
            guard let first = list.map(\.date).min() else { return .day }
            let span = calendar.dateComponents([.day], from: first, to: Date()).day ?? 0
            return span > 400 ? .month : (span > 60 ? .weekOfYear : .day)
        }
    }

    private func activityCard(_ list: [StatEvent]) -> some View {
        let unit = unit(for: list)
        let grouped = Dictionary(grouping: list) { event in
            BucketKey(date: calendar.dateInterval(of: unit, for: event.date)?.start ?? event.date, action: event.action)
        }
        let buckets = grouped.map { Bucket(date: $0.key.date, action: $0.key.action, count: $0.value.count) }
            .sorted { $0.date < $1.date }
        let start = periodStart ?? calendar.dateInterval(of: unit, for: list.map(\.date).min() ?? Date())?.start ?? Date()
        let end = calendar.dateInterval(of: unit, for: Date())?.end ?? Date()

        return StatCard(title: "Activité", symbol: "calendar") {
            Chart(buckets) { bucket in
                BarMark(x: .value("Date", bucket.date, unit: unit),
                        y: .value("Fichiers", bucket.count))
                    .foregroundStyle(by: .value("Action", bucket.action.label))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                StatEvent.Action.sorted.label: Color.green,
                StatEvent.Action.auto.label: Color.purple,
                StatEvent.Action.kept.label: Color.blue,
                StatEvent.Action.trashed.label: Color.red,
            ])
            .chartXScale(domain: start...end)
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 220)
        }
    }

    // MARK: Catégories

    private struct CategoryRow: Identifiable {
        let name: String
        let count: Int
        let bytes: Int64
        var id: String { name }
    }

    private func color(forCategory name: String) -> Color {
        if let index = state.categories.firstIndex(where: { $0.name == name }) {
            return CategoryTileLabel.color(for: index)
        }
        return .gray
    }

    private func categoryCard(_ list: [StatEvent]) -> some View {
        let rows = Dictionary(grouping: list.filter { $0.action == .sorted || $0.action == .auto }, by: \.category)
            .map { CategoryRow(name: $0.key, count: $0.value.count, bytes: $0.value.reduce(0) { $0 + $1.bytes }) }
            .sorted { $0.count > $1.count }

        return StatCard(title: "Par catégorie", symbol: "square.grid.2x2") {
            if rows.isEmpty {
                Text("Aucun fichier rangé sur cette période.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                let maxCount = max(rows.first?.count ?? 1, 1)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        CategoryBar(name: row.name,
                                    symbol: state.categories.first { $0.name == row.name }?.symbol ?? "folder",
                                    color: color(forCategory: row.name),
                                    fraction: CGFloat(row.count) / CGFloat(maxCount),
                                    detail: "\(row.count) · \(formatBytes(row.bytes))")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Swipes

    private struct SwipePart {
        let label: String
        let key: String
        let color: Color
        let count: Int
    }

    private func swipeCard(_ list: [StatEvent]) -> some View {
        let parts: [SwipePart] = [
            SwipePart(label: "Rangés", key: "→", color: .green, count: count(.sorted, in: list)),
            SwipePart(label: "Gardés", key: "←", color: .blue, count: count(.kept, in: list)),
            SwipePart(label: "Corbeille", key: "↑", color: .red, count: count(.trashed, in: list)),
            SwipePart(label: "Automatique", key: "⚡︎", color: .purple, count: count(.auto, in: list)),
        ]
        let total = max(parts.reduce(0) { $0 + $1.count }, 1)

        return StatCard(title: "Tes swipes", symbol: "hand.point.up.left.fill") {
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(parts.filter { $0.count > 0 }, id: \.label) { part in
                            Rectangle()
                                .fill(part.color.gradient)
                                .frame(width: max(4, (geo.size.width - 6) * CGFloat(part.count) / CGFloat(total)))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 16)

                ForEach(parts.filter { $0.count > 0 || $0.label != "Automatique" }, id: \.label) { part in
                    HStack(spacing: 8) {
                        KeyCap(part.key)
                        Circle().fill(part.color).frame(width: 8, height: 8)
                        Text(part.label)
                        Spacer()
                        Text("\(part.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text("\(Int((Double(part.count) / Double(total) * 100).rounded())) %")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
        .frame(width: 300)
    }

    // MARK: Le saviez-vous

    private struct Fact: Identifiable {
        let id = UUID()
        let symbol: String
        let color: Color
        let title: String
        let value: String
        let detail: String
    }

    private func funFacts(_ list: [StatEvent]) -> some View {
        let byDay = Dictionary(grouping: list) { calendar.startOfDay(for: $0.date) }
        let bestDay = byDay.max { $0.value.count < $1.value.count }
        let byHour = Dictionary(grouping: list) { calendar.component(.hour, from: $0.date) }
        let favoriteHour = byHour.max { $0.value.count < $1.value.count }?.key
        let biggest = list.filter { $0.action != .kept }.max { $0.bytes < $1.bytes }
        let folders = list.filter { $0.isFolder && $0.action != .kept }.count
        let processed = list.reduce(Int64(0)) { $0 + $1.bytes }
        let renamed = state.history.filter { $0.categoryName == AppState.renamedLabel && !$0.undone }.count
        let waiting = state.queue.count
        func plural(_ n: Int, _ word: String) -> String { "\(word)\(n > 1 ? "s" : "")" }

        var facts: [Fact] = []
        if let bestDay {
            facts.append(Fact(symbol: "trophy.fill", color: .yellow, title: "Jour record",
                              value: "\(bestDay.value.count)",
                              detail: "\(plural(bestDay.value.count, "décision")) le \(bestDay.key.formatted(.dateTime.day().month(.wide)))"))
        }
        if let favoriteHour {
            facts.append(Fact(symbol: "clock.fill", color: .teal, title: "Ton heure préférée",
                              value: "\(favoriteHour) h", detail: "c'est là que tu tries le plus"))
        }
        if let biggest, biggest.bytes > 0 {
            facts.append(Fact(symbol: "externaldrive.fill", color: .indigo, title: "Le plus gros",
                              value: formatBytes(biggest.bytes), detail: biggest.fileName))
        }
        facts.append(Fact(symbol: "scalemass.fill", color: .brown, title: "Volume traité",
                          value: formatBytes(processed), detail: "passés entre tes mains"))
        if renamed > 0 {
            facts.append(Fact(symbol: "pencil.line", color: .purple, title: "Noms plus clairs",
                              value: "\(renamed)", detail: "\(plural(renamed, "fichier")) \(plural(renamed, "renommé"))"))
        }
        if folders > 0 {
            facts.append(Fact(symbol: "folder.fill", color: .blue, title: "Dossiers",
                              value: "\(folders)", detail: "\(plural(folders, "dossier")) \(plural(folders, "trié"))"))
        }
        if waiting > 0 {
            facts.append(Fact(symbol: "tray.full.fill", color: .orange, title: "En attente",
                              value: "\(waiting)", detail: "à trier en ce moment"))
        }

        // Lignes équilibrées, jamais de trou : 4 → 2+2, 5 → 3+2, 6 → 3+3, 7 → 3+2+2…
        var rows: [[Fact]] = []
        var rest = facts[...]
        while !rest.isEmpty {
            let remaining = rest.count
            let n = remaining == 4 ? 2 : (remaining % 3 == 1 && remaining > 3 ? 2 : min(3, remaining))
            rows.append(Array(rest.prefix(n)))
            rest = rest.dropFirst(n)
        }

        return StatCard(title: "Le saviez-vous ?", symbol: "sparkles") {
            VStack(spacing: 12) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        ForEach(rows[i]) { fact in
                            FactTile(symbol: fact.symbol, color: fact.color, title: fact.title,
                                     value: fact.value, detail: fact.detail)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Série

    static func streaks(_ events: [StatEvent], calendar: Calendar) -> (current: Int, best: Int) {
        let days = Set(events.map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return (0, 0) }
        let sortedDays = days.sorted()
        var best = 1
        var run = 1
        for index in sortedDays.indices.dropFirst() {
            let gap = calendar.dateComponents([.day], from: sortedDays[index - 1], to: sortedDays[index]).day ?? 0
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }
        var current = 0
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday   // la série reste valable tant que la journée n'est pas finie
        }
        while days.contains(day) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return (current, best)
    }
}

// MARK: - Composants

private struct StatCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .hoverGlow(cornerRadius: 14)
    }
}

private struct StatTile: View {
    let symbol: String
    let color: Color
    let value: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.callout.weight(.medium))
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.25)))
        .hoverGlow(cornerRadius: 14)
    }
}

private struct FactTile: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(Circle().fill(color.opacity(0.16)))
                .hoverPop(scale: 1.15, angle: -10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(detail)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.16)))
        .hoverGlow(cornerRadius: 14)
    }
}

/// Une barre de catégorie, arrondie des deux côtés (capsule), avec effet au survol.
private struct CategoryBar: View {
    let name: String
    let symbol: String
    let color: Color
    let fraction: CGFloat
    let detail: String
    @State private var hovering = false
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            Label(name, systemImage: symbol)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(14, geo.size.width * (appeared ? fraction : 0)))
                        .shadow(color: color.opacity(hovering ? 0.45 : 0), radius: 8, y: 2)
                }
            }
            .frame(height: 12)
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .hoverHighlight(cornerRadius: 10, inset: -5)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovering = h } }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appeared = true } }
    }
}
