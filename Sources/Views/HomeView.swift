import SwiftUI

/// Premier écran : « Explorer une chaîne ». Champ de recherche en haut,
/// favoris épinglés puis chaînes récentes en dessous.
struct HomeView: View {
    @EnvironmentObject private var store: ChannelStore
    @State private var query = ""
    let open: (String) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 56) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Explorer une chaîne")
                        .font(.system(size: 72, weight: .bold))
                    Text("Retrouve et regarde les VOD Twitch, même celles qui ont été supprimées.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 28) {
                    TextField("Nom de la chaîne Twitch", text: $query)
                        .onSubmit(submit)
                        .frame(maxWidth: 1150)
                    Button(action: submit) {
                        Label("Explorer", systemImage: "arrow.right")
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(query.normalizedChannel.isEmpty)
                }
                .focusSection()

                if !store.favorites.isEmpty {
                    ChannelShelf(title: "Favoris", systemImage: "star.fill", entries: store.favorites, open: open)
                }
                if !store.history.isEmpty {
                    ChannelShelf(title: "Récents", systemImage: "clock.arrow.circlepath", entries: store.history, open: open)
                }

                Text(store.channels.isEmpty
                     ? "Les chaînes que tu explores apparaîtront ici."
                     : "Maintiens le bouton central sur une chaîne pour l'épingler en favori ou la retirer.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 70)
        }
        .screenBackground()
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
    let systemImage: String
    let entries: [ChannelEntry]
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 36) {
                    ForEach(entries) { entry in
                        ChannelCard(entry: entry) { open(entry.login) }
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
                .padding(.vertical, 30)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

private struct ChannelCard: View {
    let entry: ChannelEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                Avatar(url: entry.avatar, name: entry.displayName)
                    .frame(width: 150, height: 150)
                    .overlay(alignment: .topTrailing) {
                        if entry.pinned {
                            Image(systemName: "star.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.yellow)
                                .padding(10)
                                .glassEffect(.regular, in: .circle)
                                .offset(x: 10, y: -6)
                        }
                    }
                Text(entry.displayName)
                    .font(.headline)
                    .lineLimit(1)
            }
            .frame(width: 220)
            .padding(.vertical, 28)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 40))
    }
}
