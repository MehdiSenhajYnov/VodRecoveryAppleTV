import Foundation

struct StreamInfo: Identifiable, Hashable, Codable {
    let streamID: String
    var title: String
    var start: Date
    var duration: TimeInterval?
    var thumbnail: URL?

    var id: String { streamID }
}

struct ChannelInfo: Hashable {
    let login: String
    var displayName: String
    var avatar: URL?
    var streams: [StreamInfo]
}

/// Liste des streams récents d'une chaîne : API GraphQL de Twitch + vodvod.top,
/// fusionnées comme dans VodRecovery (vodvod complète/corrige les données Twitch).
enum TwitchAPI {
    private static let gql = URL(string: "https://gql.twitch.tv/gql")!
    private static let headers = [
        "Client-ID": "ue6666qo983tsx6so1t0vnawi233wa",
        "Accept": "application/json",
    ]

    static func channel(_ rawLogin: String) async throws -> ChannelInfo {
        let login = rawLogin.lowercased()
        async let profile = fetchProfile(login)
        async let videos = fetchVideos(login)
        async let archive = fetchVodVod(login)
        let (user, api, vodvod) = await (profile, videos, archive)

        let streams = merge(api ?? [], vodvod ?? [])
        if user == nil && streams.isEmpty {
            if api == nil && vodvod == nil { throw AppError.network }
            throw AppError.channelNotFound
        }
        return ChannelInfo(
            login: login,
            displayName: user?.name ?? login,
            avatar: user?.avatar,
            streams: streams
        )
    }

    // MARK: - Twitch GQL

    private static func fetchProfile(_ login: String) async -> (name: String, avatar: URL?)? {
        let query = "query($login: String!) { user(login: $login) { displayName profileImageURL(width: 300) } }"
        guard
            let json = try? await Net.postJSON(gql, body: ["query": query, "variables": ["login": login]], headers: headers),
            let user = ((json as? [String: Any])?["data"] as? [String: Any])?["user"] as? [String: Any]
        else { return nil }
        let name = (user["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? login
        return (name, (user["profileImageURL"] as? String).flatMap(URL.init(string:)))
    }

    private static func fetchVideos(_ login: String) async -> [StreamInfo]? {
        let query = """
        query($login: String!, $first: Int!) { user(login: $login) { videos(first: $first) { edges { node {
          id title createdAt publishedAt lengthSeconds previewThumbnailURL animatedPreviewURL
        } } } } }
        """
        guard
            let json = try? await Net.postJSON(gql, body: ["query": query, "variables": ["login": login, "first": 100]], headers: headers),
            let data = (json as? [String: Any])?["data"] as? [String: Any]
        else { return nil }
        guard let user = data["user"] as? [String: Any] else { return [] }
        let edges = ((user["videos"] as? [String: Any])?["edges"] as? [[String: Any]]) ?? []
        let cutoff = Date().addingTimeInterval(-60 * 86400)

        return edges.compactMap { edge -> StreamInfo? in
            guard
                let node = edge["node"] as? [String: Any],
                let created = parseDate((node["createdAt"] as? String) ?? (node["publishedAt"] as? String)),
                created > cutoff
            else { return nil }

            let preview = node["previewThumbnailURL"] as? String ?? ""
            let animated = node["animatedPreviewURL"] as? String ?? ""
            // Le dossier CDN des miniatures contient "<hash>_<login>_<streamID>_<epoch>" :
            // c'est l'identifiant du stream et son heure de début exacte.
            let extracted = extractStreamFolder(preview, login: login) ?? extractStreamFolder(animated, login: login)
            var start = created
            if let epoch = extracted?.epoch {
                let exact = Date(timeIntervalSince1970: epoch)
                if abs(exact.timeIntervalSince(created)) < 86400 { start = exact }
            }
            let sized = preview
                .replacingOccurrences(of: "%{width}", with: "640").replacingOccurrences(of: "%{height}", with: "360")
                .replacingOccurrences(of: "{width}", with: "640").replacingOccurrences(of: "{height}", with: "360")
            let thumb = preview.isEmpty || preview.contains("404_processing") ? nil : URL(string: sized)
            return StreamInfo(
                streamID: extracted?.streamID ?? (node["id"] as? String ?? ""),
                title: node["title"] as? String ?? "",
                start: start,
                duration: (node["lengthSeconds"] as? NSNumber)?.doubleValue,
                thumbnail: thumb
            )
        }
    }

    private static func extractStreamFolder(_ url: String, login: String) -> (streamID: String, epoch: TimeInterval)? {
        for part in url.split(separator: "/") {
            guard let range = part.range(of: "_\(login)_") else { continue }
            let pieces = part[range.upperBound...].split(separator: "_")
            if pieces.count >= 2, let epoch = TimeInterval(pieces[1]) {
                return (String(pieces[0]), epoch)
            }
        }
        return nil
    }

    // MARK: - vodvod.top (archive plus longue, heures précises)

    private static func fetchVodVod(_ login: String) async -> [StreamInfo]? {
        guard
            let url = URL(string: "https://api.vodvod.top/channels/@\(login)"),
            let response = try? await Net.get(url),
            response.0 == 200,
            let items = (try? JSONSerialization.jsonObject(with: response.1)) as? [[String: Any]]
        else { return nil }

        return items.compactMap { item -> StreamInfo? in
            guard
                let meta = item["Metadata"] as? [String: Any],
                let start = parseDate(meta["StartTime"] as? String)
            else { return nil }
            var streamID = ""
            if let s = meta["StreamID"] as? String { streamID = s }
            if let n = meta["StreamID"] as? NSNumber { streamID = n.stringValue }
            guard !streamID.isEmpty else { return nil }
            var duration: TimeInterval?
            if let hls = meta["HlsDurationSeconds"] as? [String: Any], (hls["Valid"] as? Bool) == true,
               let seconds = (hls["Float64"] as? NSNumber)?.doubleValue, seconds > 0 {
                duration = seconds
            }
            return StreamInfo(
                streamID: streamID,
                title: meta["TitleAtStart"] as? String ?? "",
                start: start,
                duration: duration,
                thumbnail: nil
            )
        }
    }

    private static func merge(_ api: [StreamInfo], _ vodvod: [StreamInfo]) -> [StreamInfo] {
        var byID: [String: StreamInfo] = [:]
        var order: [String] = []
        for stream in api where byID[stream.streamID] == nil {
            byID[stream.streamID] = stream
            order.append(stream.streamID)
        }
        for stream in vodvod {
            if var existing = byID[stream.streamID] {
                existing.start = stream.start
                if !stream.title.isEmpty { existing.title = stream.title }
                if let d = stream.duration { existing.duration = d }
                byID[stream.streamID] = existing
            } else {
                byID[stream.streamID] = stream
                order.append(stream.streamID)
            }
        }
        return order.compactMap { byID[$0] }.sorted { $0.start > $1.start }
    }

    // MARK: - Dates

    private static let iso = ISO8601DateFormatter()

    /// ISO 8601, avec ou sans fraction de seconde (vodvod en renvoie jusqu'à 9 chiffres).
    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let trimmed = value.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return iso.date(from: trimmed)
    }
}
