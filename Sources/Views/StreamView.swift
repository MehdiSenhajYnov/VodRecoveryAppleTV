import AVKit
import SwiftUI

/// Un stream : la récupération démarre toute seule, puis « Lire » est sélectionné
/// par défaut. Une seule pression suffit pour regarder.
struct StreamView: View {
    @EnvironmentObject private var store: ChannelStore
    @StateObject private var model: RecoveryModel
    @State private var playing = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case play, retry }

    init(login: String, stream: StreamInfo) {
        _model = StateObject(wrappedValue: RecoveryModel(login: login, stream: stream))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 70) {
            details
                .frame(width: 760)
            panel
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenBackground()
        .onAppear { model.start(store: store) }
        .onDisappear { model.cancel() }
        .onChange(of: model.phase) { _, phase in
            if phase == .ready { focus = .play }
            if case .failed = phase { focus = .retry }
        }
        .fullScreenCover(isPresented: $playing) {
            if let url = model.playbackURL {
                PlayerView(url: url, title: model.stream.title, resumeKey: "position.\(model.stream.streamID)")
                    .ignoresSafeArea()
            }
        }
        .alert(
            "Lecteur indisponible",
            isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.notice ?? "")
        }
    }

    // MARK: - Colonne gauche

    private var details: some View {
        VStack(alignment: .leading, spacing: 30) {
            Thumbnail(url: model.stream.thumbnail)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
            Text(model.stream.title.isEmpty ? "Stream sans titre" : model.stream.title)
                .font(.title2.weight(.bold))
                .lineLimit(3)
            VStack(alignment: .leading, spacing: 10) {
                Label(Format.longDate(model.stream.start), systemImage: "calendar")
                if let duration = Format.duration(model.prepared?.duration ?? model.stream.duration) {
                    Label(duration, systemImage: "clock")
                }
                Label("Stream \(model.stream.streamID)", systemImage: "number")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Panneau d'action (verre)

    private var panel: some View {
        VStack(alignment: .leading, spacing: 40) {
            status

            if !model.qualities.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Qualité").font(.headline).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 20) {
                            ForEach(model.qualities, id: \.self) { quality in
                                qualityChip(quality)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 4)
                    }
                    .scrollClipDisabled()
                }
                .focusSection()
            }

            if model.qualities.isEmpty == false || model.phase == .ready {
                HStack(spacing: 24) {
                    Toggle(isOn: $model.unmute) { Label("Démuter", systemImage: "speaker.wave.2") }
                    Toggle(isOn: $model.verify) { Label("Vérifier les segments", systemImage: "checkmark.shield") }
                }
                .focusSection()
            }

            actions
        }
        .padding(48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 48, style: .continuous))
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .searching(let done, let total):
            progressBlock(
                title: "Recherche de la VOD…",
                detail: total > 0 ? "\(Format.number(done)) / \(Format.number(total)) adresses testées" : "Préparation…",
                value: total > 0 ? Double(done) / Double(total) : nil
            )
        case .qualities:
            progressBlock(title: "VOD trouvée", detail: "Vérification des qualités disponibles…", value: nil)
        case .preparing(let fraction):
            progressBlock(
                title: model.verify ? "Vérification des segments…" : "Préparation de la lecture…",
                detail: model.unmute ? "Restauration du son des passages coupés" : "Lecture du son tel quel",
                value: fraction > 0 ? fraction : nil
            )
        case .ready:
            VStack(alignment: .leading, spacing: 12) {
                Label("Prêt à regarder", systemImage: "checkmark.circle.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.green)
                if let summary {
                    Text(summary).foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label("Introuvable", systemImage: "xmark.octagon.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.orange)
                Text(message).foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String? {
        guard let p = model.prepared else { return nil }
        var parts = ["\(Format.number(p.segments)) segments"]
        if p.restored > 0 { parts.append("\(Format.number(p.restored)) démutés") }
        if p.stillMuted > 0 { parts.append("\(Format.number(p.stillMuted)) encore muets") }
        if p.missing > 0 { parts.append("\(Format.number(p.missing)) manquants retirés") }
        return parts.joined(separator: " · ")
    }

    private func progressBlock(title: String, detail: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.bold))
            Group {
                if let value {
                    ProgressView(value: value)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .tint(.purple)
            Text(detail).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func qualityChip(_ quality: String) -> some View {
        let selected = quality == model.quality
        let label = Text(Recovery.label(for: quality))
            .fontWeight(selected ? .bold : .regular)
            .padding(.horizontal, 6)
        if selected {
            Button { model.select(quality) } label: { label }
                .buttonStyle(.glassProminent)
        } else {
            Button { model.select(quality) } label: { label }
                .buttonStyle(.glass)
                .disabled(model.isWorking)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch model.phase {
        case .ready:
            HStack(spacing: 24) {
                Button {
                    playing = true
                } label: {
                    Label("Lire", systemImage: "play.fill")
                        .font(.title3.weight(.bold))
                        .padding(.horizontal, 30)
                }
                .buttonStyle(.glassProminent)
                .focused($focus, equals: .play)

                ForEach(RecoveryModel.ExternalPlayer.allCases) { player in
                    Button {
                        model.open(in: player)
                    } label: {
                        Label(player.rawValue, systemImage: player == .vlc ? "play.tv" : "arrow.up.forward.app")
                    }
                    .buttonStyle(.glass)
                }
            }
            .focusSection()
            .defaultFocus($focus, .play)
        case .failed:
            Button {
                model.retry(store: store)
            } label: {
                Label("Réessayer", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.glassProminent)
            .focused($focus, equals: .retry)
        default:
            EmptyView()
        }
    }
}

/// Lecteur intégré (AVKit) avec reprise automatique là où on s'était arrêté.
struct PlayerView: UIViewControllerRepresentable {
    let url: URL
    let title: String
    let resumeKey: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let item = AVPlayerItem(url: url)
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = (title.isEmpty ? "Stream" : title) as NSString
        titleItem.extendedLanguageTag = "und"
        item.externalMetadata = [titleItem]

        let player = AVPlayer(playerItem: item)
        let saved = UserDefaults.standard.double(forKey: resumeKey)
        if saved > 60 {
            player.seek(to: CMTime(seconds: saved - 5, preferredTimescale: 600))
        }
        let controller = AVPlayerViewController()
        controller.player = player
        context.coordinator.observe(player, key: resumeKey)
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.save()
        controller.player?.pause()
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var player: AVPlayer?
        private var key = ""
        private var observer: Any?

        func observe(_ player: AVPlayer, key: String) {
            self.player = player
            self.key = key
            observer = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 15, preferredTimescale: 1), queue: .main
            ) { [weak self] _ in self?.save() }
        }

        func save() {
            guard let player, let item = player.currentItem else { return }
            let position = player.currentTime().seconds
            let duration = item.duration.seconds
            guard position.isFinite, position > 0 else { return }
            // Vidéo terminée : la prochaine lecture repart du début.
            let value = duration.isFinite && duration - position < 120 ? 0 : position
            UserDefaults.standard.set(value, forKey: key)
        }

        func stop() {
            if let observer { player?.removeTimeObserver(observer) }
            observer = nil
            player = nil
        }
    }
}
