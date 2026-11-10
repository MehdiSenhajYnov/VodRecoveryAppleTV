import SwiftUI

/// Racine autonome de VOD Recovery : utilisée par l'app seule (Main.swift)
/// comme par le hub MyApps, qui l'embarque telle quelle.
public struct VodRecoveryRoot: View {
    @StateObject private var store = ChannelStore()

    public init() {}

    public var body: some View {
        RootView()
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
    }
}

/// Fourni par une app hôte (MyApps) : appelé quand on appuie sur « Retour »
/// depuis l'écran d'accueil. Absent quand l'app tourne seule.
private struct ExitAppKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var exitApp: (() -> Void)? {
        get { self[ExitAppKey.self] }
        set { self[ExitAppKey.self] = newValue }
    }
}

extension View {
    /// Branche le bouton « Retour » de l'écran d'accueil sur l'app hôte.
    public func exitAppHandler(_ action: (() -> Void)?) -> some View {
        environment(\.exitApp, action)
    }
}

enum Route: Hashable {
    case channel(String)
    case stream(login: String, StreamInfo)
}

struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView { path.append(.channel($0)) }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .channel(let login):
                        ChannelView(login: login) { path.append(.stream(login: login, $0)) }
                    case .stream(let login, let stream):
                        StreamView(login: login, stream: stream)
                    }
                }
        }
    }
}

/// Palette sobre : presque noir, un seul accent lavande désaturé utilisé avec parcimonie.
/// Pensée pour une pièce sombre : rien de saturé, pas de grands aplats lumineux.
enum Theme {
    static let base = Color(red: 0.045, green: 0.047, blue: 0.058)
    static let raised = Color(red: 0.11, green: 0.115, blue: 0.135)
    static let accent = Color(red: 0.68, green: 0.64, blue: 0.92)
    static let hPad: CGFloat = 80
}

/// Fond quasi noir avec une très légère lueur froide en haut : donne juste
/// assez de matière au verre (Liquid Glass) sans éblouir.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.base
            RadialGradient(
                colors: [Color(red: 0.30, green: 0.32, blue: 0.45).opacity(0.22), .clear],
                center: .init(x: 0.2, y: -0.1), startRadius: 0, endRadius: 1400
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    func screenBackground() -> some View {
        background(AppBackground())
    }
}

/// Style de bouton « soulevé » : l'élément grossit doucement et s'éclaire au focus.
struct LiftButtonStyle: ButtonStyle {
    var scale: CGFloat = 1.08

    func makeBody(configuration: Configuration) -> some View {
        LiftBody(configuration: configuration, scale: scale)
    }

    private struct LiftBody: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? scale - 0.04 : (focused ? scale : 1))
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 24, y: 14)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: focused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

struct Avatar: View {
    let url: URL?
    let name: String

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Theme.raised
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .clipShape(Circle())
    }
}
