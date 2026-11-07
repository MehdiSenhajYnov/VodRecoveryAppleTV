import SwiftUI
import UIKit

/// Tout le parcours d'un stream en une seule étape pour l'utilisateur :
/// retrouver la VOD → choisir la meilleure qualité → préparer la playlist → prêt à lire.
@MainActor
final class RecoveryModel: ObservableObject {
    enum Phase: Equatable {
        case searching(done: Int, total: Int)
        case qualities
        case preparing(Double)
        case ready
        case failed(String)
    }

    let login: String
    let stream: StreamInfo

    @Published private(set) var phase: Phase = .searching(done: 0, total: 0)
    @Published private(set) var qualities: [String] = []
    @Published private(set) var quality: String?
    @Published private(set) var prepared: Recovery.Prepared?
    @Published private(set) var playbackURL: URL?
    @Published var notice: String?

    @Published var unmute: Bool {
        didSet { UserDefaults.standard.set(unmute, forKey: "unmute"); if found != nil { prepare() } }
    }
    @Published var verify: Bool {
        didSet { UserDefaults.standard.set(verify, forKey: "verify"); if found != nil { prepare() } }
    }

    private var found: URL?
    private var task: Task<Void, Never>?

    init(login: String, stream: StreamInfo) {
        self.login = login
        self.stream = stream
        let defaults = UserDefaults.standard
        unmute = defaults.object(forKey: "unmute") as? Bool ?? true
        verify = defaults.object(forKey: "verify") as? Bool ?? true
    }

    var isWorking: Bool {
        switch phase {
        case .ready, .failed: return false
        default: return true
        }
    }

    func start(store: ChannelStore) {
        guard task == nil, found == nil else { return }
        task = Task { await run(store: store) }
    }

    func retry(store: ChannelStore) {
        task?.cancel()
        task = nil
        found = nil
        phase = .searching(done: 0, total: 0)
        start(store: store)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func select(_ quality: String) {
        guard quality != self.quality else { return }
        self.quality = quality
        UserDefaults.standard.set(quality, forKey: "preferredQuality")
        prepare()
    }

    private func run(store: ChannelStore) async {
        var url: URL?
        if let cached = store.recoveredURL(for: stream.streamID), await Recovery.isReachable(cached) {
            url = cached
        } else {
            url = await Recovery.findPlaylist(login: login, streamID: stream.streamID, start: stream.start) { done, total in
                Task { @MainActor [weak self] in
                    if case .searching = self?.phase { self?.phase = .searching(done: done, total: total) }
                }
            }
        }
        if Task.isCancelled { return }
        guard let url else {
            phase = .failed(AppError.vodNotFound.localizedDescription)
            return
        }
        found = url
        store.remember(url, for: stream.streamID)

        phase = .qualities
        let available = await Recovery.availableQualities(for: url)
        if Task.isCancelled { return }
        qualities = available
        let preferred = UserDefaults.standard.string(forKey: "preferredQuality")
        quality = available.first(where: { $0 == preferred }) ?? available.first
        await runPreparation()
    }

    private func prepare() {
        task?.cancel()
        task = Task { await runPreparation() }
    }

    private func runPreparation() async {
        guard let found, let quality else { return }
        phase = .preparing(0)
        playbackURL = nil
        do {
            let result = try await Recovery.prepare(
                Recovery.url(found, quality: quality), unmute: unmute, verify: verify
            ) { fraction in
                Task { @MainActor [weak self] in
                    if case .preparing = self?.phase { self?.phase = .preparing(fraction) }
                }
            }
            if Task.isCancelled { return }
            let name = "\(stream.streamID)-\(quality)-\(unmute ? "u" : "m")\(verify ? "v" : "n")"
            playbackURL = try await PlaylistServer.shared.publish(result.text, name: name)
            prepared = result
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Lecteurs externes

    enum ExternalPlayer: String, CaseIterable, Identifiable {
        case vlc = "VLC"
        case infuse = "Infuse"

        var id: String { rawValue }

        func url(for media: URL) -> URL? {
            let encoded = media.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            switch self {
            case .vlc: return URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encoded)")
            case .infuse: return URL(string: "infuse://x-callback-url/play?url=\(encoded)")
            }
        }
    }

    func open(in player: ExternalPlayer) {
        guard let playbackURL, let target = player.url(for: playbackURL) else { return }
        let app = UIApplication.shared
        guard app.canOpenURL(target) else {
            notice = "\(player.rawValue) n'est pas installé sur cette Apple TV. Installe-le depuis l'App Store, ou utilise le lecteur intégré."
            return
        }
        // Le lecteur externe télécharge la playlist au démarrage : on garde l'app
        // (et donc le serveur local) éveillée quelques secondes en arrière-plan.
        var token = UIBackgroundTaskIdentifier.invalid
        token = app.beginBackgroundTask(withName: "playlist") {
            app.endBackgroundTask(token)
            token = .invalid
        }
        app.open(target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            if token != .invalid { app.endBackgroundTask(token) }
        }
    }
}
