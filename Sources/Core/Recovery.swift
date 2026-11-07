import CryptoKit
import Foundation

/// Moteur de récupération, porté de VodRecovery :
/// 1. reconstruit l'URL CDN du stream (sha1 de "<login>_<streamID>_<epoch>") ;
/// 2. liste les qualités disponibles ;
/// 3. prépare une playlist lisible : audio restauré (segments « muted ») et
///    segments vérifiés un par un, les manquants étant retirés proprement.
enum Recovery {
    static let domains = [
        "https://vod-secure.twitch.tv/",
        "https://vod-metro.twitch.tv/",
        "https://vod-pop-secure.twitch.tv/",
        "https://ds0h3roq6wcgc.cloudfront.net/",
        "https://d2nvs31859zcd8.cloudfront.net/",
        "https://d2aba1wr3818hz.cloudfront.net/",
        "https://d3c27h4odz752x.cloudfront.net/",
        "https://dgeft87wbj63p.cloudfront.net/",
        "https://d1m7jfoe9zdc1j.cloudfront.net/",
        "https://d3vd9lfkzbru3h.cloudfront.net/",
        "https://ddacn6pr5v0tl.cloudfront.net/",
        "https://d3aqoihi2n8ty8.cloudfront.net/",
        "https://d3fi1amfgojobc.cloudfront.net/",
        "https://d3stzm2eumvgb4.cloudfront.net/",
        "https://d2vi6trrdongqn.cloudfront.net/",
        "https://d1ndex63qxojbr.cloudfront.net/",
    ]

    static let resolutions = [
        "chunked", "2160p60", "2160p30", "1440p60", "1440p30", "1080p60", "1080p30", "1080p20",
        "720p60", "720p30", "720p20", "480p60", "480p30", "360p60", "360p30", "160p60", "160p30",
    ]

    static let playlistNames = ["index-dvr.m3u8", "index.m3u8"]
    static let commonQualities = ["chunked", "1080p60", "720p60"]
    static let moreQualities = ["1080p30", "720p30", "720p20", "480p30"]

    static func label(for quality: String) -> String {
        quality == "chunked" ? "Source" : quality
    }

    // MARK: - 1. Retrouver la playlist

    static func folder(login: String, streamID: String, epoch: Int) -> String {
        let key = "\(login)_\(streamID)_\(epoch)"
        let hex = Insecure.SHA1.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(20)) + "_" + key
    }

    /// Candidats triés du plus probable au moins probable : l'heure exacte d'abord,
    /// puis en s'en éloignant seconde par seconde (-30 s … +59 s).
    static func candidates(login: String, streamID: String, start: Date, qualities: [String]) -> [URL] {
        let base = Int(start.timeIntervalSince1970)
        let offsets = (-30..<60).sorted { abs($0) == abs($1) ? $0 > $1 : abs($0) < abs($1) }
        var urls: [URL] = []
        urls.reserveCapacity(offsets.count * qualities.count * domains.count * playlistNames.count)
        for offset in offsets {
            let path = folder(login: login, streamID: streamID, epoch: base + offset)
            for quality in qualities {
                for domain in domains {
                    for name in playlistNames {
                        if let url = URL(string: "\(domain)\(path)/\(quality)/\(name)") { urls.append(url) }
                    }
                }
            }
        }
        return urls
    }

    static func isPlaylist(_ url: URL) async -> Bool {
        for _ in 0..<2 {
            if Task.isCancelled { return false }
            do {
                let (code, data) = try await Net.get(url)
                if code == 200 { return String(decoding: data.prefix(256), as: UTF8.self).contains("#EXTM3U") }
                if code == 403 || code == 404 || code == 410 { return false }
            } catch {
                if Task.isCancelled { return false }
            }
        }
        return false
    }

    /// Une playlist bloquée (403) reste exploitable si ses segments répondent.
    static func isReachable(_ playlist: URL) async -> Bool {
        if await isPlaylist(playlist) { return true }
        let dir = playlist.deletingLastPathComponent()
        for segment in ["0.ts", "0.mp4"] {
            if await Net.head(dir.appendingPathComponent(segment)) == .ok { return true }
        }
        return false
    }

    static func findPlaylist(
        login: String,
        streamID: String,
        start: Date,
        progress: @escaping (_ done: Int, _ total: Int) -> Void
    ) async -> URL? {
        let login = login.lowercased()
        let first = candidates(login: login, streamID: streamID, start: start, qualities: commonQualities)
        let second = candidates(login: login, streamID: streamID, start: start, qualities: moreQualities)
        let total = first.count + second.count

        if let hit = await firstMatch(first, concurrency: 48, progress: { progress($0, total) }, isPlaylist) {
            return hit
        }
        if Task.isCancelled { return nil }
        return await firstMatch(second, concurrency: 48, progress: { progress(first.count + $0, total) }, isPlaylist)
    }

    // MARK: - 2. Qualités

    static func url(_ found: URL, quality: String) -> URL {
        found.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(quality)
            .appendingPathComponent(found.lastPathComponent)
    }

    static func availableQualities(for found: URL) async -> [String] {
        let current = found.deletingLastPathComponent().lastPathComponent
        let checks = await concurrentMap(resolutions, concurrency: 8) { quality -> Bool in
            quality == current ? true : await isReachable(url(found, quality: quality))
        }
        var result = zip(resolutions, checks).filter { $0.1 }.map { $0.0 }
        if !result.contains(current) { result.insert(current, at: 0) }
        return result
    }

    // MARK: - 3. Playlist démutée et vérifiée

    struct Prepared {
        var text: String
        var segments: Int
        var restored: Int
        var stillMuted: Int
        var missing: Int
        var duration: TimeInterval
    }

    private enum Outcome {
        case keep(URL, restored: Bool, muted: Bool)
        case drop
    }

    static func prepare(
        _ playlistURL: URL,
        unmute: Bool,
        verify: Bool,
        progress: @escaping (Double) -> Void
    ) async throws -> Prepared {
        let base = playlistURL.deletingLastPathComponent()
        let (code, data) = try await Net.get(playlistURL)
        let body = String(decoding: data, as: UTF8.self)

        let text: String
        var alreadyProbed = false
        if code == 200 && body.contains("#EXTM3U") {
            text = body
        } else if let generated = await generateFromSegments(base: base, progress: progress) {
            // Playlist retirée par Twitch mais segments encore en ligne : on la reconstruit.
            text = generated
            alreadyProbed = true
        } else {
            throw AppError.playlistUnavailable
        }

        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let fmp4 = text.contains("#EXT-X-MAP")
        let segmentURLs = lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { URL(string: $0, relativeTo: base)?.absoluteURL ?? base.appendingPathComponent($0) }

        let outcomes: [Outcome]
        if alreadyProbed || (!unmute && !verify) {
            outcomes = segmentURLs.map { .keep($0, restored: false, muted: isMarked($0.lastPathComponent, fmp4: fmp4)) }
        } else {
            outcomes = await concurrentMap(segmentURLs, concurrency: 40, progress: progress) { url in
                await choose(url, fmp4: fmp4, unmute: unmute, verify: verify)
            }
        }
        if Task.isCancelled { throw CancellationError() }
        return assemble(lines: lines, base: base, outcomes: outcomes)
    }

    /// Segment « muet » selon la convention Twitch (inversée entre .ts et fMP4).
    static func isMarked(_ name: String, fmp4: Bool) -> Bool {
        fmp4 ? (name.contains("-muted") && !name.contains("-unmuted"))
            : (name.contains("-muted") || name.contains("-unmuted"))
    }

    /// Versions avec l'audio d'origine, de la plus sûre à la moins sûre.
    static func alternatives(_ url: URL, fmp4: Bool) -> [URL] {
        let name = url.lastPathComponent
        let plain = name.replacingOccurrences(of: "-unmuted", with: "").replacingOccurrences(of: "-muted", with: "")
        var names = [plain]
        if fmp4, name.contains("-muted") {
            names.append(name.replacingOccurrences(of: "-muted", with: "-unmuted"))
        } else if !fmp4, name.contains("-unmuted") {
            names.append(name.replacingOccurrences(of: "-unmuted", with: "-muted"))
        }
        let dir = url.deletingLastPathComponent()
        return names.filter { $0 != name }.map { dir.appendingPathComponent($0) }
    }

    private static func choose(_ url: URL, fmp4: Bool, unmute: Bool, verify: Bool) async -> Outcome {
        let marked = isMarked(url.lastPathComponent, fmp4: fmp4)
        if unmute && marked {
            for candidate in alternatives(url, fmp4: fmp4) {
                if await Net.head(candidate) == .ok { return .keep(candidate, restored: true, muted: false) }
            }
        }
        if verify, await Net.head(url) == .missing { return .drop }
        return .keep(url, restored: false, muted: marked)
    }

    private static func isSegmentTag(_ line: String) -> Bool {
        line.hasPrefix("#EXTINF") || line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME") || line.hasPrefix("#EXT-X-BYTERANGE")
    }

    private static func assemble(lines: [String], base: URL, outcomes: [Outcome]) -> Prepared {
        var out: [String] = []
        var pending: [String] = []
        var needsDiscontinuity = false
        var hasPlaylistType = false
        var segment = 0
        var kept = 0, restored = 0, muted = 0, missing = 0
        var duration: TimeInterval = 0

        for line in lines where !line.isEmpty {
            if line.hasPrefix("#") {
                if line == "#EXT-X-ENDLIST" { continue }
                if line.hasPrefix("#EXT-X-PLAYLIST-TYPE") {
                    hasPlaylistType = true
                    pending.append("#EXT-X-PLAYLIST-TYPE:VOD")
                } else if line.hasPrefix("#EXT-X-MAP") {
                    pending.append(absolutizeURIs(line, base: base))
                } else {
                    pending.append(line)
                }
                continue
            }
            guard segment < outcomes.count else { break }
            let outcome = outcomes[segment]
            segment += 1
            switch outcome {
            case .drop:
                missing += 1
                pending.removeAll(where: isSegmentTag)
                if kept > 0 { needsDiscontinuity = true }
            case .keep(let url, let wasRestored, let isMuted):
                if needsDiscontinuity {
                    let index = pending.firstIndex(where: { $0.hasPrefix("#EXTINF") }) ?? pending.count
                    pending.insert("#EXT-X-DISCONTINUITY", at: index)
                    needsDiscontinuity = false
                }
                for tag in pending where tag.hasPrefix("#EXTINF:") {
                    duration += Double(tag.dropFirst(8).split(separator: ",").first ?? "") ?? 0
                }
                out.append(contentsOf: pending)
                out.append(url.absoluteString)
                pending.removeAll()
                kept += 1
                if wasRestored { restored += 1 }
                if isMuted { muted += 1 }
            }
        }
        out.append(contentsOf: pending.filter { !isSegmentTag($0) })
        if !hasPlaylistType, let header = out.firstIndex(of: "#EXTM3U") {
            out.insert("#EXT-X-PLAYLIST-TYPE:VOD", at: header + 1)
        }
        out.append("#EXT-X-ENDLIST")
        return Prepared(
            text: out.joined(separator: "\n") + "\n",
            segments: kept,
            restored: restored,
            stillMuted: muted,
            missing: missing,
            duration: duration
        )
    }

    private static func absolutizeURIs(_ line: String, base: URL) -> String {
        guard let start = line.range(of: "URI=\"") else { return line }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return line }
        let uri = String(rest[..<end])
        let absolute = URL(string: uri, relativeTo: base)?.absoluteString ?? uri
        return line.replacingCharacters(in: start.upperBound..<end, with: absolute)
    }

    // MARK: - Playlist reconstruite à partir des segments

    private static func probeSegment(_ base: URL, _ n: Int, ext: String) async -> String? {
        for attempt in 0..<2 {
            var transient = false
            for suffix in ["", "-unmuted", "-muted"] {
                switch await Net.head(base.appendingPathComponent("\(n)\(suffix)\(ext)"), attempts: 2) {
                case .ok: return suffix
                case .missing: continue
                case .unknown: transient = true
                }
            }
            if !transient || attempt == 1 { return nil }
        }
        return nil
    }

    static func generateFromSegments(base: URL, progress: @escaping (Double) -> Void) async -> String? {
        var ext = ".ts"
        if await probeSegment(base, 0, ext: ext) == nil {
            ext = ".mp4"
            if await probeSegment(base, 0, ext: ext) == nil { return nil }
        }
        // Recherche du dernier segment : doublement puis dichotomie.
        var low = 0
        var high = 100
        while await probeSegment(base, high, ext: ext) != nil {
            low = high
            high *= 2
            if high > 50_000 || Task.isCancelled { break }
        }
        while low < high {
            let mid = (low + high + 1) / 2
            if await probeSegment(base, mid, ext: ext) != nil { low = mid } else { high = mid - 1 }
        }
        let suffixes = await concurrentMap(Array(0...low), concurrency: 48, progress: progress) { n in
            await probeSegment(base, n, ext: ext)
        }

        let fmp4 = ext == ".mp4"
        var lines = [
            "#EXTM3U", "#EXT-X-VERSION:\(fmp4 ? 6 : 3)", "#EXT-X-TARGETDURATION:10",
            "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-MEDIA-SEQUENCE:0",
        ]
        if fmp4 { lines.append("#EXT-X-MAP:URI=\"\(base.appendingPathComponent("init-0.mp4").absoluteString)\"") }
        var gap = false
        for (n, suffix) in suffixes.enumerated() {
            guard let suffix else {
                gap = true
                continue
            }
            if gap {
                lines.append("#EXT-X-DISCONTINUITY")
                gap = false
            }
            lines.append("#EXTINF:10.000,")
            lines.append(base.appendingPathComponent("\(n)\(suffix)\(ext)").absoluteString)
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n")
    }
}
