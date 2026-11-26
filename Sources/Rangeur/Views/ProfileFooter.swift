import SwiftUI
import AppKit
import Collaboration

/// Le nom et la photo de la session macOS.
enum UserProfile {
    static var fullName: String {
        let name = NSFullUserName()
        return name.isEmpty ? NSUserName() : name
    }

    static let picture: NSImage? = {
        let identity = CBIdentity(name: NSUserName(), authority: CBIdentityAuthority.default())
        return (identity as? CBUserIdentity)?.image
    }()

    static var initials: String {
        let parts = fullName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

struct Avatar: View {
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let picture = UserProfile.picture {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color.purple, Color.indigo],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(UserProfile.initials)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1)))
    }
}

/// Pied de la barre latérale, comme dans Claude : photo, nom de session, et un menu.
struct ProfileFooter: View {
    @EnvironmentObject var state: AppState
    @State private var showMenu = false
    @State private var hovering = false

    private var subtitle: String {
        let streak = StatsView.streaks(state.stats, calendar: .current).current
        let sorted = state.stats.filter { $0.action != .kept }.count
        if streak >= 2 { return "🔥 \(streak) jours d'affilée" }
        return "\(sorted) fichier\(sorted > 1 ? "s" : "") trié\(sorted > 1 ? "s" : "")"
    }

    var body: some View {
        Button { showMenu.toggle() } label: {
            HStack(spacing: 10) {
                Avatar(size: 30)
                    .scaleEffect(hovering ? 1.08 : 1)
                    .rotationEffect(.degrees(hovering ? -4 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
                VStack(alignment: .leading, spacing: 1) {
                    Text(UserProfile.fullName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassOr(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hovering || showMenu ? 0.09 : 0.05))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showMenu, arrowEdge: .top) {
            ProfileMenu { showMenu = false }
                .environmentObject(state)
        }
    }
}

private struct ProfileMenu: View {
    @EnvironmentObject var state: AppState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Avatar(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(UserProfile.fullName).font(.headline)
                    Text(NSUserName()).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().padding(.vertical, 4)

            row("Statistiques", "chart.bar.xaxis") { state.selectedSection = .stats }
            row("Activité", "clock.arrow.circlepath") { state.selectedSection = .activity }
            row("Choisir un dossier à trier…", "folder.badge.plus") { state.chooseFolder() }
            row("Réglages", "gearshape") { state.selectedSection = .settings }

            Divider().padding(.vertical, 4)

            row("Site de Rangeur", "globe") { NSWorkspace.shared.open(Links.site) }
            CoffeeButton { close(); NSWorkspace.shared.open(Links.coffee) }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)

            Divider().padding(.vertical, 4)

            row("Quitter Rangeur", "power") { NSApp.terminate(nil) }
        }
        .padding(8)
        .frame(width: 250)
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        MenuRow(title: title, symbol: symbol) {
            close()
            action()
        }
    }
}

private struct MenuRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(hovering ? Color.white : Color.secondary)
                Text(title)
                Spacer()
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Le bouton café jaune, comme sur titelive.me.
struct CoffeeButton: View {
    var title = "Offrir un café"
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .rotationEffect(.degrees(hovering ? -12 : 0))
                Text(title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(Color(red: 1, green: hovering ? 0.914 : 0.867, blue: hovering ? 0.30 : 0)))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.85), lineWidth: 1.2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("buymeacoffee.com/titelive")
    }
}
