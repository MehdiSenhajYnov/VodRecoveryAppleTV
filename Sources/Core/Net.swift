import Foundation

/// Petit client HTTP partagé : délais courts, pas de cache, quelques essais
/// sur les erreurs réseau (jamais sur un 403/404 qui est une vraie réponse).
enum Net {
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 40
        config.httpMaximumConnectionsPerHost = 16
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    enum Probe { case ok, missing, unknown }

    /// HEAD sur une ressource : `.missing` uniquement si le serveur dit qu'elle n'existe pas.
    static func head(_ url: URL, attempts: Int = 3) async -> Probe {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        for attempt in 0..<attempts {
            if Task.isCancelled { return .unknown }
            do {
                let (_, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 || code == 206 { return .ok }
                if code == 403 || code == 404 || code == 410 { return .missing }
            } catch {
                if Task.isCancelled { return .unknown }
            }
            try? await Task.sleep(nanoseconds: UInt64(250_000_000 * (attempt + 1)))
        }
        return .unknown
    }

    static func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Int, Data) {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    static func postJSON(_ url: URL, body: [String: Any], headers: [String: String]) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.network }
        return try JSONSerialization.jsonObject(with: data)
    }
}

enum AppError: LocalizedError {
    case network
    case channelNotFound
    case vodNotFound
    case playlistUnavailable

    var errorDescription: String? {
        switch self {
        case .network:
            return "Connexion impossible. Vérifie le réseau de l'Apple TV."
        case .channelNotFound:
            return "Chaîne introuvable. Vérifie l'orthographe du nom."
        case .vodNotFound:
            return "Aucune VOD trouvée. Twitch a sans doute déjà supprimé les fichiers de ce stream."
        case .playlistUnavailable:
            return "La VOD a été trouvée mais ses segments ne sont plus accessibles."
        }
    }
}

/// `map` concurrent, borné, qui conserve l'ordre des résultats.
func concurrentMap<T, R>(
    _ items: [T],
    concurrency: Int,
    progress: ((Double) -> Void)? = nil,
    _ transform: @escaping (T) async -> R
) async -> [R] {
    guard !items.isEmpty else { return [] }
    return await withTaskGroup(of: (Int, R).self) { group in
        var results = [R?](repeating: nil, count: items.count)
        var next = 0
        var done = 0
        while next < min(concurrency, items.count) {
            let index = next
            let item = items[index]
            group.addTask { (index, await transform(item)) }
            next += 1
        }
        while let pair = await group.next() {
            results[pair.0] = pair.1
            done += 1
            if done % 8 == 0 || done == items.count {
                progress?(Double(done) / Double(items.count))
            }
            if next < items.count {
                let index = next
                let item = items[index]
                group.addTask { (index, await transform(item)) }
                next += 1
            }
        }
        return results.map { $0! }
    }
}

/// Premier élément qui satisfait `check`, en testant `concurrency` éléments à la fois
/// dans l'ordre donné ; annule le reste dès qu'un résultat est trouvé.
func firstMatch<T>(
    _ items: [T],
    concurrency: Int,
    progress: ((Int) -> Void)? = nil,
    _ check: @escaping (T) async -> Bool
) async -> T? {
    guard !items.isEmpty else { return nil }
    return await withTaskGroup(of: T?.self) { group in
        var next = 0
        var done = 0
        while next < min(concurrency, items.count) {
            let item = items[next]
            group.addTask { await check(item) ? item : nil }
            next += 1
        }
        while let result = await group.next() {
            done += 1
            if done % 16 == 0 { progress?(done) }
            if let result {
                group.cancelAll()
                return result
            }
            if Task.isCancelled {
                group.cancelAll()
                return nil
            }
            if next < items.count {
                let item = items[next]
                group.addTask { await check(item) ? item : nil }
                next += 1
            }
        }
        progress?(done)
        return nil
    }
}
