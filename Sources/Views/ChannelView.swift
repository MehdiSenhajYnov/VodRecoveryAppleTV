import SwiftUI

/// Streams récents d'une chaîne, en grille de vignettes.
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

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 50) {
                header
                switch state {
                case .loading:
                    HStack(spacing: 24) {
                        ProgressView()
                        Text("Recherche des streams…").foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
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
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 50), count: 3),
                            alignment: .leading,
                            spacing: 64
                        ) {
                            ForEach(info.streams) { stream in
                                StreamCard(stream: stream) { openStream(stream) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
        }
        .screenBackground()
        .task { await load() }
    }

    private var entry: ChannelEntry? { store.entry(login) }

    private var header: some View {
        HStack(spacing: 36) {
            Avatar(url: displayAvatar, name: displayName)
                .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 60, weight: .bold))
                if case .loaded(let info) = state {
                    Text(info.streams.count == 1 ? "1 stream" : "\(info.streams.count) streams")
                        .foregroundStyle(.secondary)
                }
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

private struct StreamCard: View {
    let stream: StreamInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Thumbnail(url: stream.thumbnail)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .bottomTrailing) {
                        if let duration = Format.duration(stream.duration) {
                            Text(duration)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .glassEffect(.regular, in: .capsule)
                                .padding(14)
                        }
                    }
                VStack(alignment: .leading, spacing: 8) {
                    Text(stream.title.isEmpty ? "Stream sans titre" : stream.title)
                        .font(.headline)
                        .lineLimit(2, reservesSpace: true)
                    Text("\(Format.date(stream.start)) · \(Format.relative(stream.start))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(22)
            }
        }
        .buttonStyle(.card)
    }
}

struct Thumbnail: View {
    let url: URL?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.18, blue: 0.70), Color(red: 0.10, green: 0.08, blue: 0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.35))
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
