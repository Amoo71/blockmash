import Foundation
import Network

// Minimaler HTTP/1.1-Client auf Network.framework. Jede Verbindung ist fest an ein Netzwerk
// (WLAN/Mobilfunk/Ethernet) gebunden – das ist der Kern von Plexo: verschiedene Blöcke derselben
// Datei laufen gleichzeitig über verschiedene Netzwerke (Range-Requests).

enum HTTPError: LocalizedError {
    case invalidURL
    case connectionFailed(String)
    case timeout
    case badResponse
    case status(Int)
    case closed
    case rangeIgnored
    case redirect(URL)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültiger Link"
        case .connectionFailed(let reason): return "Verbindung fehlgeschlagen: \(reason)"
        case .timeout: return "Zeitüberschreitung"
        case .badResponse: return "Ungültige Serverantwort"
        case .status(let code): return "Server antwortet mit HTTP \(code)"
        case .closed: return "Verbindung vom Server geschlossen"
        case .rangeIgnored: return "Server ignoriert Teil-Anfragen"
        case .redirect: return "Weiterleitung"
        }
    }

    /// Der Server lehnt weitere Verbindungen ab (zu viele Streams).
    var isRefusal: Bool {
        if case .status(let code) = self { return code == 429 || code == 503 || code == 403 }
        return false
    }
}

struct HTTPResponseHead {
    let status: Int
    let headers: [String: String]

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    var contentLength: Int64? {
        header("content-length").flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }

    var isChunked: Bool { header("transfer-encoding")?.lowercased().contains("chunked") == true }
    var keepAlive: Bool { header("connection")?.lowercased().contains("close") != true }

    /// Beginn aus "Content-Range: bytes 100-199/1000".
    var contentRangeStart: Int64? {
        guard let cr = header("content-range")?.lowercased(), let r = cr.range(of: "bytes ") else { return nil }
        let rest = cr[r.upperBound...]
        guard let dash = rest.firstIndex(of: "-") else { return nil }
        return Int64(rest[..<dash].trimmingCharacters(in: .whitespaces))
    }
}

final class HTTPConnection: @unchecked Sendable {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    let host: String
    let port: Int
    let secure: Bool
    let kind: NetworkKind

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "plexo.http")
    private var buffer = Data()
    private(set) var isReusable = false
    private var started = false
    private var waitingReason: String?

    init(url: URL, kind: NetworkKind) throws {
        guard let host = url.host, !host.isEmpty, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { throw HTTPError.invalidURL }
        self.host = host
        self.secure = scheme == "https"
        self.port = url.port ?? (secure ? 443 : 80)
        self.kind = kind
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { throw HTTPError.invalidURL }

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        tcp.noDelay = true
        tcp.enableKeepalive = true
        let params: NWParameters
        if secure {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
            params = NWParameters(tls: tls, tcp: tcp)
        } else {
            params = NWParameters(tls: nil, tcp: tcp)
        }
        if let iface = InterfaceRegistry.interface(for: kind) {
            params.requiredInterface = iface
        } else {
            params.requiredInterfaceType = kind.interfaceType
        }
        params.prohibitExpensivePaths = false
        params.prohibitConstrainedPaths = false
        connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
    }

    func matches(_ url: URL) -> Bool {
        let s = url.scheme?.lowercased() == "https"
        return url.host == host && (url.port ?? (s ? 443 : 80)) == port && s == secure
    }

    func cancel() {
        isReusable = false
        connection.cancel()
    }

    // MARK: - Verbindungsaufbau

    func start(timeout: TimeInterval = 20) async throws {
        if started { return }
        started = true
        let kindName = kind.defaultName
        let hostName = host
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                let once = Once()
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        once.run {
                            let path = self?.connection.currentPath
                            let iface = path?.availableInterfaces.first?.name ?? "?"
                            DiagLog.add("Verbindung \(kindName) bereit über \(iface) → \(hostName)")
                            cont.resume()
                        }
                    case .failed(let error):
                        once.run {
                            DiagLog.add("Verbindung \(kindName) fehlgeschlagen: \(error.localizedDescription)")
                            cont.resume(throwing: HTTPError.connectionFailed(error.localizedDescription))
                        }
                    case .waiting(let error):
                        // Mobilfunk-Modem wacht noch auf o. Ä. – weiter warten, bis "ready" oder Timeout.
                        self?.waitingReason = error.localizedDescription
                        DiagLog.add("Verbindung \(kindName) wartet: \(error.localizedDescription)")
                    case .cancelled:
                        once.run { cont.resume(throwing: CancellationError()) }
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    once.run {
                        let reason = self?.waitingReason
                        DiagLog.add("Verbindung \(kindName) Timeout\(reason.map { " (\($0))" } ?? "")")
                        self?.connection.cancel()
                        if let reason {
                            cont.resume(throwing: HTTPError.connectionFailed(reason))
                        } else {
                            cont.resume(throwing: HTTPError.timeout)
                        }
                    }
                }
            }
        } onCancel: {
            self.connection.cancel()
        }
    }

    // MARK: - Senden / Empfangen

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    /// Nächstes Datenstück; nil = Verbindung beendet. Bricht nach `timeout` Sekunden ohne Daten ab.
    private func receiveChunk(timeout: TimeInterval = 30) async throws -> Data? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data?, Error>) in
                let once = Once()
                let timer = DispatchWorkItem { [weak self] in
                    once.run {
                        self?.connection.cancel()
                        cont.resume(throwing: HTTPError.timeout)
                    }
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { data, _, isComplete, error in
                    timer.cancel()
                    once.run {
                        if let data, !data.isEmpty {
                            cont.resume(returning: data)
                        } else if let error {
                            cont.resume(throwing: error)
                        } else if isComplete {
                            cont.resume(returning: nil)
                        } else {
                            cont.resume(returning: Data())
                        }
                    }
                }
                queue.asyncAfter(deadline: .now() + timeout, execute: timer)
            }
        } onCancel: {
            self.connection.cancel()
        }
    }

    private func fill() async throws -> Bool {
        guard let chunk = try await receiveChunk() else { return false }
        buffer.append(chunk)
        return true
    }

    private func take(_ count: Int) -> Data {
        let n = min(count, buffer.count)
        let head = Data(buffer.prefix(n))
        buffer = Data(buffer.dropFirst(n))
        return head
    }

    private func readLine() async throws -> String {
        let crlf = Data("\r\n".utf8)
        while true {
            if let r = buffer.range(of: crlf) {
                let line = Data(buffer[buffer.startIndex..<r.lowerBound])
                buffer = Data(buffer[r.upperBound...])
                return String(decoding: line, as: UTF8.self)
            }
            if buffer.count > 64 * 1024 { throw HTTPError.badResponse }
            guard try await fill() else { throw HTTPError.closed }
        }
    }

    // MARK: - Anfrage

    /// Sendet GET (optional mit Range) und liest den Antwortkopf.
    func request(_ url: URL, headers: [String: String], rangeStart: Int64?, rangeEnd: Int64?) async throws -> HTTPResponseHead {
        isReusable = false
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw HTTPError.invalidURL }
        var target = comps.percentEncodedPath.isEmpty ? "/" : comps.percentEncodedPath
        if let q = comps.percentEncodedQuery, !q.isEmpty { target += "?" + q }
        let defaultPort = secure ? 443 : 80
        let hostHeader = port == defaultPort ? host : "\(host):\(port)"

        var lines = ["GET \(target) HTTP/1.1", "Host: \(hostHeader)"]
        var hasUA = false
        for (k, v) in headers {
            let lower = k.lowercased()
            if lower == "host" || lower == "range" || lower == "connection" || lower == "accept-encoding" { continue }
            if lower == "user-agent" { hasUA = true }
            lines.append("\(k): \(v)")
        }
        if !hasUA { lines.append("User-Agent: \(Self.userAgent)") }
        lines.append("Accept: */*")
        lines.append("Accept-Encoding: identity")
        lines.append("Connection: keep-alive")
        if let rangeStart {
            if let rangeEnd {
                lines.append("Range: bytes=\(rangeStart)-\(rangeEnd)")
            } else {
                lines.append("Range: bytes=\(rangeStart)-")
            }
        }
        let raw = lines.joined(separator: "\r\n") + "\r\n\r\n"
        try await send(Data(raw.utf8))

        while true {
            let statusLine = try await readLine()
            let parts = statusLine.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]) else {
                throw HTTPError.badResponse
            }
            var fields: [String: String] = [:]
            while true {
                let line = try await readLine()
                if line.isEmpty { break }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if let existing = fields[name] {
                    fields[name] = existing + ", " + value
                } else {
                    fields[name] = value
                }
            }
            if (100..<200).contains(code) { continue }
            let head = HTTPResponseHead(status: code, headers: fields)
            if (300..<400).contains(code), let loc = head.header("location"),
               let next = URL(string: loc, relativeTo: url)?.absoluteURL {
                try await discardBody(head)
                throw HTTPError.redirect(next)
            }
            return head
        }
    }

    private func discardBody(_ head: HTTPResponseHead) async throws {
        if let len = head.contentLength, len < 1_000_000 {
            try await readBody(head) { _ in true }
        } else {
            cancel()
        }
    }

    /// Liest den Körper der Antwort. `onData` gibt false zurück, um abzubrechen.
    func readBody(_ head: HTTPResponseHead, onData: (Data) async throws -> Bool) async throws {
        isReusable = false
        if head.isChunked {
            while true {
                let sizeLine = try await readLine()
                let hex = sizeLine.split(separator: ";").first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                guard let size = Int(hex, radix: 16) else { throw HTTPError.badResponse }
                if size == 0 {
                    while try await readLine().isEmpty == false {}
                    break
                }
                var remaining = size
                while remaining > 0 {
                    if buffer.isEmpty {
                        guard try await fill() else { throw HTTPError.closed }
                    }
                    let piece = take(remaining)
                    remaining -= piece.count
                    let keep = try await onData(piece)
                if !keep {
                        cancel()
                        return
                    }
                }
                _ = try await readLine()
            }
            isReusable = head.keepAlive
            return
        }

        if let length = head.contentLength {
            var remaining = length
            if !buffer.isEmpty && remaining > 0 {
                let piece = take(Int(min(Int64(buffer.count), remaining)))
                remaining -= Int64(piece.count)
                let keep = try await onData(piece)
                if !keep {
                    cancel()
                    return
                }
            }
            while remaining > 0 {
                guard let chunk = try await receiveChunk() else { throw HTTPError.closed }
                if chunk.isEmpty { continue }
                var piece = chunk
                if Int64(chunk.count) > remaining {
                    piece = Data(chunk.prefix(Int(remaining)))
                    buffer.append(Data(chunk.dropFirst(Int(remaining))))
                }
                remaining -= Int64(piece.count)
                let keep = try await onData(piece)
                if !keep {
                    cancel()
                    return
                }
            }
            isReusable = head.keepAlive
            return
        }

        // Bis zum Verbindungsende lesen.
        if !buffer.isEmpty {
            let piece = take(buffer.count)
            let keep = try await onData(piece)
                if !keep {
                cancel()
                return
            }
        }
        while let chunk = try await receiveChunk() {
            if chunk.isEmpty { continue }
            let keep = try await onData(chunk)
                if !keep {
                cancel()
                return
            }
        }
        isReusable = false
    }
}
