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
        ZStack(alignment: .bottomLeading) {
            backdrop
            VStack(alignment: .leading, spacing: 44) {
                titleBlock
                status
                actions
                options
            }
            .frame(maxWidth: 1250, alignment: .leading)
            .padding(.horizontal, Theme.hPad)
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .ignoresSafeArea()
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

    // MARK: - Fond : la vignette du stream en plein écran, assombrie

    private var backdrop: some View {
        ZStack {
            Theme.base
            Thumbnail(url: model.stream.thumbnail)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.55)
            LinearGradient(
                stops: [
                    .init(color: Theme.base.opacity(0.98), location: 0),
                    .init(color: Theme.base.opacity(0.85), location: 0.38),
                    .init(color: Theme.base.opacity(0.25), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                colors: [.clear, Theme.base.opacity(0.9)],
                startPoint: .center, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Titre et infos

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.entry(model.login)?.displayName ?? model.login)
                .font(.headline)
                .foregroundStyle(Theme.accent)
            Text(model.stream.title.isEmpty ? "Stream sans titre" : model.stream.title)
                .font(.system(size: 58, weight: .bold))
                .lineLimit(2)
            HStack(spacing: 14) {
                Text(Format.longDate(model.stream.start))
                if let duration = Format.duration(model.prepared?.duration ?? model.stream.duration) {
                    Text("·")
                    Text(duration)
                }
                if let quality = model.quality {
                    Text(Recovery.label(for: quality))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary, lineWidth: 1.5))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - État de la récupération

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
                detail: model.unmute ? "Restauration du son des passages coupés" : "Son d'origine",
                value: fraction > 0 ? fraction : nil
            )
        case .ready:
            Label(summary ?? "Prêt à regarder", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange.opacity(0.9))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ProgressView()
                Text(title).font(.title3.weight(.semibold))
            }
            if let value {
                ProgressView(value: value)
                    .frame(maxWidth: 700)
            }
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

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
                        .padding(.horizontal, 34)
                }
                .buttonStyle(.glassProminent)
                .focused($focus, equals: .play)

                ForEach(RecoveryModel.ExternalPlayer.allCases) { player in
                    Button {
                        model.open(in: player)
                    } label: {
                        Label(player.rawValue, systemImage: "arrow.up.forward.app")
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

    // MARK: - Réglages (qualité, son, vérification)

    @ViewBuilder
    private var options: some View {
        if !model.qualities.isEmpty {
            HStack(spacing: 18) {
                ForEach(model.qualities, id: \.self) { quality in
                    qualityChip(quality)
                }
                Divider().frame(height: 40).padding(.horizontal, 10)
                optionChip("Démuter", isOn: model.unmute) { model.unmute.toggle() }
                optionChip("Vérifier les segments", isOn: model.verify) { model.verify.toggle() }
            }
            .font(.callout)
            .focusSection()
        }
    }

    @ViewBuilder
    private func qualityChip(_ quality: String) -> some View {
        let selected = quality == model.quality
        Button { model.select(quality) } label: {
            Text(Recovery.label(for: quality))
                .fontWeight(selected ? .bold : .regular)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .buttonStyle(.glass)
        .disabled(model.isWorking && !selected)
    }

    private func optionChip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? .primary : .secondary)
        }
        .buttonStyle(.glass)
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
