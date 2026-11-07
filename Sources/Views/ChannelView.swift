import SwiftUI

/// Streams récents d'une chaîne : grille de vignettes sur toute la largeur.
struct ChannelView: View {
    @EnvironmentObject private var store: ChannelStore
    let login: String
    let openStream: (StreamInfo) -> Void

    private enum LoadState {
        case loading
        case loaded(ChannelInfo)
        case failed(String)
    }

    @State private var state: LoadState = .loading

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 48, alignment: .top), count: 4)

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 56) {
                header
                content
            }
            .padding(.horizontal, Theme.hPad)
            .padding(.top, 60)
            .padding(.bottom, 80)
        }
        .ignoresSafeArea(edges: .horizontal)
        .background {
            ZStack {
                AppBackground()
                // Halo très discret de la photo de profil derrière l'en-tête.
                Avatar(url: displayAvatar, name: displayName)
                    .frame(width: 900, height: 900)
                    .blur(radius: 160)
                    .opacity(0.16)
                    .offset(x: -600, y: -520)
                    .ignoresSafeArea()
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 24) {
                ProgressView()
                Text("Recherche des streams…").foregroundStyle(.secondary)
            }
            .padding(.top, 20)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 24) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.title3)
                Button("Réessayer", systemImage: "arrow.clockwise") { Task { await load() } }
                    .buttonStyle(.glass)
            }
        case .loaded(let info):
            if info.streams.isEmpty {
                Label("Aucun stream récent trouvé pour cette chaîne.", systemImage: "tray")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
                    ForEach(info.streams) { stream in
                        StreamCard(stream: stream) { openStream(stream) }
                    }
                }
                .focusSection()
            }
        }
    }

    private var entry: ChannelEntry? { store.entry(login) }

    private var header: some View {
        HStack(spacing: 36) {
            Avatar(url: displayAvatar, name: displayName)
                .frame(width: 140, height: 140)
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 2))
            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 64, weight: .bold))
                    .lineLimit(1)
                Group {
                    if case .loaded(let info) = state {
                        Text(info.streams.count == 1 ? "1 stream récent" : "\(info.streams.count) streams récents")
                    } else {
                        Text("twitch.tv/\(login)")
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let entry {
                Button {
                    withAnimation { store.togglePin(entry.login) }
                } label: {
                    Label(entry.pinned ? "Favori" : "Épingler", systemImage: entry.pinned ? "star.fill" : "star")
                }
                .buttonStyle(.glass)
            }
        }
        .focusSection()
    }

    private var displayName: String {
        if case .loaded(let info) = state { return info.displayName }
        return entry?.displayName ?? login
    }

    private var displayAvatar: URL? {
        if case .loaded(let info) = state, let avatar = info.avatar { return avatar }
        return entry?.avatar
    }

    private func load() async {
        state = .loading
        do {
            let info = try await TwitchAPI.channel(login)
            store.record(info)
            state = .loaded(info)
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// Vignette façon app TV d'Apple : l'image seule se soulève, le texte reste dessous.
private struct StreamCard: View {
    let stream: StreamInfo
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: action) {
                Thumbnail(url: stream.thumbnail)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .bottomTrailing) {
                        if let duration = Format.duration(stream.duration) {
                            Text(duration)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.65), in: .capsule)
                                .padding(12)
                        }
                    }
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 6) {
                Text(stream.title.isEmpty ? "Stream sans titre" : stream.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                Text("\(Format.date(stream.start)) · \(Format.relative(stream.start))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct Thumbnail: View {
    let url: URL?

    var body: some View {
        ZStack {
            Theme.raised
            Image(systemName: "play.rectangle")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white.opacity(0.18))
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .clipped()
    }
}
