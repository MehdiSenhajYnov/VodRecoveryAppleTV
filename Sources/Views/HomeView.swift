import SwiftUI

/// Premier écran : « Explorer une chaîne ». Recherche en haut, puis favoris
/// épinglés et chaînes récentes en rangées qui vont d'un bord à l'autre.
struct HomeView: View {
    @EnvironmentObject private var store: ChannelStore
    @Environment(\.exitApp) private var exitApp
    @State private var query = ""
    let open: (String) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 64) {
                header
                    .padding(.horizontal, Theme.hPad)

                if !store.favorites.isEmpty {
                    ChannelShelf(title: "Favoris", entries: store.favorites, open: open)
                }
                if !store.history.isEmpty {
                    ChannelShelf(title: "Récents", entries: store.history, open: open)
                }

                if store.channels.isEmpty {
                    emptyState.padding(.horizontal, Theme.hPad)
                } else {
                    Text("Maintiens le bouton central sur une chaîne pour l'épingler ou la retirer.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, Theme.hPad)
                }
            }
            .padding(.top, 70)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ignoresSafeArea(edges: .horizontal)
        .screenBackground()
        .onExitCommand(perform: exitApp)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                Label("VOD Recovery", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Text("Explorer une chaîne")
                    .font(.system(size: 76, weight: .bold))
            }

            HStack(spacing: 24) {
                TextField("Nom de la chaîne Twitch", text: $query)
                    .onSubmit(submit)
                    .frame(maxWidth: .infinity)
                Button(action: submit) {
                    Label("Explorer", systemImage: "arrow.right")
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.glassProminent)
                .disabled(query.normalizedChannel.isEmpty)
            }
            .focusSection()
        }
    }

    private var emptyState: some View {
        HStack(spacing: 28) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Tape le nom d'une chaîne pour commencer").font(.title3.weight(.semibold))
                Text("Les chaînes que tu explores apparaîtront ici, et tu pourras épingler tes préférées.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    private func submit() {
        let login = query.normalizedChannel
        guard !login.isEmpty else { return }
        query = ""
        open(login)
    }
}

private struct ChannelShelf: View {
    @EnvironmentObject private var store: ChannelStore
    let title: String
    let entries: [ChannelEntry]
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.hPad)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 48) {
                    ForEach(entries) { entry in
                        Button { open(entry.login) } label: { ChannelCard(entry: entry) }
                            .buttonStyle(LiftButtonStyle())
                            .contextMenu {
                                Button(
                                    entry.pinned ? "Retirer des favoris" : "Épingler en favori",
                                    systemImage: entry.pinned ? "star.slash" : "star"
                                ) { withAnimation { store.togglePin(entry.login) } }
                                Button("Supprimer de l'historique", systemImage: "trash", role: .destructive) {
                                    withAnimation { store.remove(entry.login) }
                                }
                            }
                    }
                }
                .padding(.horizontal, Theme.hPad)
                .padding(.vertical, 36)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

private struct ChannelCard: View {
    let entry: ChannelEntry
    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(spacing: 22) {
            Avatar(url: entry.avatar, name: entry.displayName)
                .frame(width: 190, height: 190)
                .overlay(Circle().strokeBorder(.white.opacity(focused ? 0.9 : 0.08), lineWidth: focused ? 5 : 2))
                .overlay(alignment: .bottomTrailing) {
                    if entry.pinned {
                        Image(systemName: "star.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(12)
                            .glassEffect(.regular, in: .circle)
                    }
                }
            Text(entry.displayName)
                .font(.headline)
                .foregroundStyle(focused ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 230)
        }
    }
}
