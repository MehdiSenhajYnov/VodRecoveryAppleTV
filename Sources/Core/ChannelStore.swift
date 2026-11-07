import Foundation
import SwiftUI

struct ChannelEntry: Codable, Identifiable, Hashable {
    var login: String
    var displayName: String
    var avatar: URL?
    var lastSearched: Date
    var pinned: Bool

    var id: String { login }
}

/// Historique des chaînes (favoris épinglés en haut) et URLs déjà retrouvées,
/// pour qu'une VOD déjà récupérée se relance instantanément.
@MainActor
final class ChannelStore: ObservableObject {
    @Published private(set) var channels: [ChannelEntry] = []
    private var recovered: [String: String] = [:]
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "channels"),
           let saved = try? JSONDecoder().decode([ChannelEntry].self, from: data) {
            channels = saved
        }
        recovered = defaults.dictionary(forKey: "recovered") as? [String: String] ?? [:]
    }

    var favorites: [ChannelEntry] {
        channels.filter(\.pinned).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var history: [ChannelEntry] {
        channels.filter { !$0.pinned }.sorted { $0.lastSearched > $1.lastSearched }
    }

    func entry(_ login: String) -> ChannelEntry? {
        channels.first { $0.login == login }
    }

    func record(_ info: ChannelInfo) {
        if let index = channels.firstIndex(where: { $0.login == info.login }) {
            channels[index].displayName = info.displayName
            channels[index].avatar = info.avatar ?? channels[index].avatar
            channels[index].lastSearched = Date()
        } else {
            channels.append(ChannelEntry(
                login: info.login, displayName: info.displayName, avatar: info.avatar,
                lastSearched: Date(), pinned: false
            ))
        }
        let overflow = history.dropFirst(30).map(\.login)
        channels.removeAll { overflow.contains($0.login) }
        save()
    }

    func togglePin(_ login: String) {
        guard let index = channels.firstIndex(where: { $0.login == login }) else { return }
        channels[index].pinned.toggle()
        save()
    }

    func remove(_ login: String) {
        channels.removeAll { $0.login == login }
        save()
    }

    func recoveredURL(for streamID: String) -> URL? {
        recovered[streamID].flatMap(URL.init(string:))
    }

    func remember(_ url: URL, for streamID: String) {
        recovered[streamID] = url.absoluteString
        defaults.set(recovered, forKey: "recovered")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(channels) {
            defaults.set(data, forKey: "channels")
        }
    }
}
