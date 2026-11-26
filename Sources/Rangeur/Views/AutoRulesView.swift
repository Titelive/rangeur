import SwiftUI

/// Les règles automatiques : « quand un fichier … depuis n jours, alors … ».
struct AutoRulesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if state.autoRules.isEmpty {
                    suggestions
                } else {
                    ForEach($state.autoRules) { $rule in
                        AutoRuleCard(rule: $rule) { state.removeRule(rule.id) }
                    }
                }

                Text("Les règles actives s'appliquent au lancement, puis toutes les heures ; celles réglées sur « tout de suite » s'appliquent dès qu'un fichier arrive. Par sécurité, un fichier modifié il y a moins d'une minute n'est jamais touché, les fichiers gardés et les exceptions sont respectés, et rien n'est supprimé définitivement : tout passe par la Corbeille et s'annule depuis l'Activité.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .navigationTitle("Règles")
        .toolbar {
            ToolbarItemGroup {
                templatesMenu
                Button { state.addRule() } label: { Label("Nouvelle règle", systemImage: "plus") }
                Button { state.runRules(manual: true) } label: { Label("Appliquer maintenant", systemImage: "play.fill") }
                    .disabled(!state.autoRules.contains { $0.enabled })
                    .help("Appliquer maintenant les règles actives")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Laisse Rangeur faire le ménage")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Choisis un modèle ou crée ta règle : quand un fichier est là depuis un certain temps, Rangeur le range, le déplace ou le met à la corbeille.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let result = state.lastRulesResult, let date = state.lastRulesRun {
                Text("\(result) · \(date.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var templatesMenu: some View {
        Menu {
            ForEach(Array(state.ruleTemplates().enumerated()), id: \.offset) { _, group in
                Section(group.section) {
                    ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                        Button(item.0) { add(item.1) }
                    }
                }
            }
        } label: {
            Label("Modèles", systemImage: "wand.and.stars")
        }
    }

    private func add(_ template: AutoRule) {
        var rule = template
        rule.enabled = true
        state.addRule(rule)
    }

    /// Premier affichage : quelques modèles en grandes tuiles.
    private var suggestions: some View {
        let picks = state.ruleTemplates().flatMap { $0.items }
        let featured = [0, 3, 6, 7, 8, 9].compactMap { $0 < picks.count ? picks[$0] : nil }
        return VStack(alignment: .leading, spacing: 10) {
            Text("POUR COMMENCER")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(featured.enumerated()), id: \.offset) { _, item in
                    Button { add(item.1) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.1.action.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(item.1.action == .trash ? Color.red : Color.accentColor)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.primary.opacity(0.06)))
                            Text(item.0)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassOr(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05))
                    }
                    .hoverGlow(cornerRadius: 14)
                }
            }
        }
    }
}

/// Une règle, écrite comme une phrase.
private struct AutoRuleCard: View {
    @EnvironmentObject var state: AppState
    @Binding var rule: AutoRule
    let onDelete: () -> Void
    @State private var showMatches = false
    @State private var matches: [URL] = []

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Toggle("Active", isOn: $rule.enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Text("Quand").foregroundStyle(.secondary)
                    Picker("", selection: targetTag) {
                        Text("un fichier").tag("any")
                        Divider()
                        ForEach(state.categories) { c in
                            Label(c.name, systemImage: c.symbol).tag("cat:" + c.id.uuidString)
                        }
                        Divider()
                        Text("un nom qui correspond à…").tag("pattern")
                        Text("un fichier gardé").tag("kept")
                        Text("un téléchargement abandonné").tag("partial")
                    }
                    .labelsHidden()
                    .fixedSize()
                    if case .pattern = rule.target {
                        TextField("", text: patternText, prompt: Text(".dmg, Facture*, *devis*"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 180)
                    }
                    Spacer()
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Supprimer cette règle")
                        .hoverPop(angle: -8)
                }

                HStack(spacing: 8) {
                    Picker("", selection: $rule.basis) {
                        ForEach(AutoRule.Basis.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Stepper(value: $rule.days, in: 0...3650) {
                        Text(rule.days == 0 ? "tout de suite" : "\(rule.days) jour\(rule.days > 1 ? "s" : "")")
                            .monospacedDigit()
                            .frame(minWidth: 90, alignment: .leading)
                    }
                    .fixedSize()
                    Picker("", selection: $rule.extra) {
                        ForEach(AutoRule.Extra.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $rule.action) {
                        ForEach(AutoRule.Action.allCases) { a in
                            Label(a.label, systemImage: a.symbol).tag(a)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if rule.action == .moveTo {
                        TextField("", text: $rule.folder, prompt: Text("Archives"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)
                    }
                    Spacer()
                    Button {
                        showMatches.toggle()
                    } label: {
                        Text(matches.isEmpty ? "Aucun fichier concerné"
                             : "\(matches.count) fichier\(matches.count > 1 ? "s" : "") concerné\(matches.count > 1 ? "s" : "") maintenant")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(matches.isEmpty ? Color.secondary : (rule.action == .trash ? Color.red : Color.accentColor))
                    }
                    .buttonStyle(.borderless)
                    .disabled(matches.isEmpty)
                    .popover(isPresented: $showMatches, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(rule.enabled ? "Prochaine application :" : "Si tu actives la règle :")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(matches.prefix(20), id: \.self) { url in
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable().frame(width: 18, height: 18)
                                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            if matches.count > 20 {
                                Text("… et \(matches.count - 20) autres").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(width: 320)
                    }
                }
            }
            .padding(6)
        }
        .opacity(rule.enabled ? 1 : 0.6)
        .task(id: rule) { matches = state.ruleMatches(rule) }
        .onChange(of: state.queue) { _ in matches = state.ruleMatches(rule) }
        .onChange(of: state.lastRulesRun) { _ in matches = state.ruleMatches(rule) }
        .hoverGlow(cornerRadius: 10)
    }

    private var targetTag: Binding<String> {
        Binding(
            get: {
                switch rule.target {
                case .any: return "any"
                case .kept: return "kept"
                case .partial: return "partial"
                case .pattern: return "pattern"
                case .category(let id): return "cat:" + id.uuidString
                }
            },
            set: { value in
                switch value {
                case "any": rule.target = .any
                case "kept": rule.target = .kept; rule.action = .unkeep
                case "partial": rule.target = .partial; rule.action = .trash
                case "pattern":
                    if case .pattern = rule.target {} else { rule.target = .pattern("") }
                default:
                    if value.hasPrefix("cat:"), let id = UUID(uuidString: String(value.dropFirst(4))) {
                        rule.target = .category(id)
                    }
                }
            }
        )
    }

    private var patternText: Binding<String> {
        Binding(
            get: { if case .pattern(let p) = rule.target { return p } else { return "" } },
            set: { rule.target = .pattern($0) }
        )
    }
}
