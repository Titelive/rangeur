import SwiftUI
import AppKit

@main
struct RangeurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Rangeur", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 800)
        }
        .defaultSize(width: 1020, height: 880)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Site de Rangeur") { NSWorkspace.shared.open(Links.site) }
                Button("Offrir un café ☕️") { NSWorkspace.shared.open(Links.coffee) }
                Divider()
                Button("Écrire à l'auteur…") { NSWorkspace.shared.open(Links.contact) }
            }
            CommandGroup(replacing: .newItem) {
                Button("Choisir un dossier à trier…") { state.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Menu("Trier un dossier récent") {
                    ForEach(AppState.quickFolders) { folder in
                        Button(folder.name) { state.selectFolder(folder.url) }
                    }
                    if !state.otherRecentFolders.isEmpty {
                        Divider()
                        ForEach(state.otherRecentFolders, id: \.self) { url in
                            Button(FileManager.default.displayName(atPath: url.path)) { state.selectFolder(url) }
                        }
                    }
                }
                Divider()
                Button("Tout ranger d'un coup") { state.organize(manual: true) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            MenuBarLabel()
                .environmentObject(state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nécessaire quand l'app est lancée depuis Xcode (paquet Swift) pour avoir une fenêtre au premier plan.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // Rangeur reste dans la barre des menus
    }
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case triage, activity, stats, automations, rules, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .triage: return "À trier"
        case .activity: return "Activité"
        case .stats: return "Statistiques"
        case .automations: return "Règles"
        case .rules: return "Catégories"
        case .settings: return "Réglages"
        }
    }

    var symbol: String {
        switch self {
        case .triage: return "rectangle.stack"
        case .activity: return "clock.arrow.circlepath"
        case .stats: return "chart.bar.xaxis"
        case .automations: return "clock.arrow.2.circlepath"
        case .rules: return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $state.selectedSection) { item in
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.symbol).hoverPop(scale: 1.2)
                }
                    .badge(item == .triage ? state.queue.count
                           : item == .automations ? state.autoRules.filter(\.enabled).count : 0)
                    .tag(item)
            }
            .safeAreaInset(edge: .bottom) {
                ProfileFooter()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                if let error = state.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            state.errorMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                }

                switch state.selectedSection ?? .triage {
                case .triage: TriageView()
                case .activity: ActivityView()
                case .stats: StatsView()
                case .automations: AutoRulesView()
                case .rules: RulesView()
                case .settings: SettingsView()
                }
            }
            // Une seule surface de la barre de titre jusqu'en bas : pas de bande de couleur différente
            // derrière le bouton de la barre latérale.
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
    }
}

/// Icône de la barre des menus. Toujours affichée, elle sert aussi à rouvrir la fenêtre
/// quand on clique sur une notification alors que la fenêtre est fermée.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: state.queue.isEmpty ? "tray" : "tray.full")
            .onChange(of: state.openWindowRequest) { _ in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(state.queue.isEmpty
             ? "Tout est rangé"
             : "\(state.queue.count) fichier\(state.queue.count > 1 ? "s" : "") à trier")
        Divider()
        Button("Trier mes fichiers…") {
            state.selectedSection = .triage
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Choisir un dossier à trier…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            state.chooseFolder()
        }
        Button("Tout ranger d'un coup") { state.organize(manual: true) }
        Toggle("Rangement automatique", isOn: $state.autoMode)
        Divider()
        Button("Quitter Rangeur") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Liens vers le site et Buy Me a Coffee.
enum Links {
    static let site = URL(string: "https://titelive.me/rangeur/")!
    static let coffee = URL(string: "https://buymeacoffee.com/titelive")!
    static let contact = URL(string: "https://titelive.me/rangeur/#idee")!
    static let author = URL(string: "https://titelive.me")!
}
