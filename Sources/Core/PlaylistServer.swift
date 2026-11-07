import Foundation
import Network

/// Mini serveur HTTP local (127.0.0.1 uniquement) qui sert les playlists préparées.
/// Le lecteur intégré comme VLC/Infuse lisent ainsi la version démutée et vérifiée ;
/// les segments, eux, sont téléchargés directement depuis le CDN de Twitch.
final class PlaylistServer {
    static let shared = PlaylistServer()

    private let queue = DispatchQueue(label: "vodrecovery.playlist-server")
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var playlists: [String: String] = [:]

    func publish(_ text: String, name: String) async throws -> URL {
        let port = try await ensureRunning()
        queue.sync { playlists[name] = text }
        return URL(string: "http://127.0.0.1:\(port)/\(name).m3u8")!
    }

    private func ensureRunning() async throws -> UInt16 {
        if let current = queue.sync(execute: { self.listener != nil && self.port != 0 ? self.port : nil }) {
            return current
        }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !resumed {
                        resumed = true
                        continuation.resume()
                    }
                case .failed(let error):
                    self?.reset()
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    self?.reset()
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        let port = listener.port?.rawValue ?? 0
        queue.sync {
            self.listener = listener
            self.port = port
        }
        return port
    }

    private func reset() {
        listener = nil
        port = 0
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let file = path.split(separator: "?").first.map(String.init) ?? path
            let name = (file.split(separator: "/").last.map(String.init) ?? "")
                .replacingOccurrences(of: ".m3u8", with: "")
            let isHead = request.hasPrefix("HEAD")

            var response: Data
            if let body = self.playlists[name] {
                let payload = Data(body.utf8)
                response = Data("""
                HTTP/1.1 200 OK\r
                Content-Type: application/vnd.apple.mpegurl\r
                Content-Length: \(payload.count)\r
                Cache-Control: no-cache\r
                Connection: close\r
                \r

                """.utf8)
                if !isHead { response.append(payload) }
            } else {
                response = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            }
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
