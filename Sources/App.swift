import SwiftUI

@main
struct VodRecoveryApp: App {
    @StateObject private var store = ChannelStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
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

/// Fond sombre coloré : donne de la matière au verre (Liquid Glass) au-dessus.
struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.05, blue: 0.20), Color(red: 0.02, green: 0.02, blue: 0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.57, green: 0.27, blue: 1.0).opacity(0.45))
                .frame(width: 1000, height: 1000)
                .blur(radius: 240)
                .offset(x: -650, y: -420)
            Circle()
                .fill(Color(red: 0.12, green: 0.50, blue: 1.0).opacity(0.28))
                .frame(width: 900, height: 900)
                .blur(radius: 260)
                .offset(x: 720, y: 460)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func screenBackground() -> some View {
        background(AppBackground())
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
                LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(Circle())
    }
}
