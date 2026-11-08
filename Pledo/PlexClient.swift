import Foundation

// Plex-API-Client – entspricht PlexRestService, LoginService und PlexLibraryIterator aus pledo.

enum PlexError: LocalizedError {
    case http(Int, String?)
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverUnreachable(String)
    case missingData(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, _): return "HTTP-Fehler \(code)"
        case .invalidURL: return "Ungültige URL"
        case .invalidResponse: return "Ungültige Antwort vom Server"
        case .unauthorized: return "Nicht autorisiert – bitte erneut anmelden"
        case .serverUnreachable(let name): return "Server \(name) ist nicht erreichbar"
        case .missingData(let what): return "Fehlende Daten: \(what)"
        }
    }
}

typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String? {
        if let s = self[key] as? String { return s }
        if let n = self[key] as? NSNumber { return n.stringValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let n = self[key] as? NSNumber { return n.intValue }
        if let s = self[key] as? String { return Int(s) }
        return nil
    }

    func int64(_ key: String) -> Int64? {
        if let n = self[key] as? NSNumber { return n.int64Value }
        if let s = self[key] as? String { return Int64(s) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let n = self[key] as? NSNumber { return n.doubleValue }
        if let s = self[key] as? String { return Double(s) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let n = self[key] as? NSNumber { return n.boolValue }
        if let s = self[key] as? String { return s == "1" || s.lowercased() == "true" }
        return nil
    }

    func arr(_ key: String) -> [JSONObject] {
        self[key] as? [JSONObject] ?? []
    }

    func obj(_ key: String) -> JSONObject? {
        self[key] as? JSONObject
    }
}

final class PlexClient: @unchecked Sendable {
    static let shared = PlexClient()
    static let product = "Pledo iOS"

    let clientIdentifier: String
    private let session: URLSession

    init() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "plexClientIdentifier") {
            clientIdentifier = id
        } else {
            let id = UUID().uuidString
            defaults.set(id, forKey: "plexClientIdentifier")
            clientIdentifier = id
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func headers(token: String?) -> [String: String] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var h: [String: String] = [
            "Accept": "application/json",
            "X-Plex-Product": Self.product,
            "X-Plex-Version": appVersion,
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Platform": "iOS",
            "X-Plex-Platform-Version": "\(os.majorVersion).\(os.minorVersion)",
            "X-Plex-Device": "iPhone",
            "X-Plex-Device-Name": "Pledo iOS",
            "X-Plex-Model": "iPhone"
        ]
        if let token { h["X-Plex-Token"] = token }
        return h
    }

    // MARK: - URL-Helfer

    func makeURL(_ base: String, _ path: String, query: [String: String] = [:]) throws -> URL {
        var b = base
        while b.hasSuffix("/") { b.removeLast() }
        let p = path.hasPrefix("/") ? path : "/" + path
        var comps = URLComponents(string: b + p)
        if comps == nil, let encoded = p.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            comps = URLComponents(string: b + encoded)
        }
        guard var components = comps else { throw PlexError.invalidURL }
        if !query.isEmpty {
            var items = components.queryItems ?? []
            for (k, v) in query.sorted(by: { $0.key < $1.key }) {
                items.append(URLQueryItem(name: k, value: v))
            }
            components.queryItems = items
        }
        guard let url = components.url else { throw PlexError.invalidURL }
        return url
    }

    static func formEncode(_ dict: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return dict.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }

    func requestJSON(_ url: URL, token: String?, method: String = "GET", form: [String: String]? = nil,
                     timeout: TimeInterval = 30) async throws -> Any {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        for (k, v) in headers(token: token) { request.setValue(v, forHTTPHeaderField: k) }
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncode(form).data(using: .utf8)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlexError.invalidResponse }
        if http.statusCode == 401 { throw PlexError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw PlexError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8))
        }
        if data.isEmpty { return JSONObject() }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    // MARK: - Anmeldung (plex.tv)

    struct Pin: Sendable {
        let id: Int
        let code: String
    }

    func createPin() async throws -> Pin {
        let url = try makeURL("https://plex.tv", "/api/v2/pins", query: ["strong": "true"])
        let json = try await requestJSON(url, token: nil, method: "POST") as? JSONObject
        guard let json, let id = json.int("id"), let code = json.str("code") else {
            throw PlexError.missingData("PIN")
        }
        return Pin(id: id, code: code)
    }

    func authURL(for pin: Pin) -> URL {
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
        let s = "https://app.plex.tv/auth#?clientID=\(enc(clientIdentifier))&code=\(enc(pin.code))"
            + "&context%5Bdevice%5D%5Bproduct%5D=\(enc(Self.product))"
        return URL(string: s) ?? URL(string: "https://app.plex.tv")!
    }

    func checkPin(_ pin: Pin) async throws -> String? {
        let url = try makeURL("https://plex.tv", "/api/v2/pins/\(pin.id)", query: ["code": pin.code])
        let json = try await requestJSON(url, token: nil) as? JSONObject
        guard let token = json?.str("authToken"), !token.isEmpty else { return nil }
        return token
    }

    func signIn(login: String, password: String, verificationCode: String?) async throws -> String {
        let url = try makeURL("https://plex.tv", "/api/v2/users/signin")
        var form = ["login": login, "password": password, "rememberMe": "true"]
        if let verificationCode, !verificationCode.isEmpty { form["verificationCode"] = verificationCode }
        let json = try await requestJSON(url, token: nil, method: "POST", form: form) as? JSONObject
        guard let token = json?.str("authToken"), !token.isEmpty else { throw PlexError.missingData("Token") }
        return token
    }

    func account(token: String) async throws -> PlexAccount {
        let url = try makeURL("https://plex.tv", "/api/v2/user")
        guard let json = try await requestJSON(url, token: token) as? JSONObject else {
            throw PlexError.invalidResponse
        }
        return PlexAccount(id: json.int("id"), uuid: json.str("uuid"), username: json.str("username"),
                           title: json.str("title"), email: json.str("email"),
                           authToken: json.str("authToken") ?? token)
    }

    // MARK: - Server & Verbindungen

    func servers(token: String) async throws -> [PlexServer] {
        let url = try makeURL("https://clients.plex.tv", "/api/v2/resources",
                              query: ["includeHttps": "1", "includeRelay": "1", "includeIPv6": "1"])
        guard let list = try await requestJSON(url, token: token) as? [JSONObject] else {
            throw PlexError.invalidResponse
        }
        return list.compactMap { r -> PlexServer? in
            let provides = (r.str("provides") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard provides.contains("server"), let id = r.str("clientIdentifier") else { return nil }
            let connections = r.arr("connections").compactMap { c -> ServerConnection? in
                guard let uri = c.str("uri") else { return nil }
                return ServerConnection(uri: uri, address: c.str("address") ?? "",
                                        protocolName: c.str("protocol") ?? "https", port: c.int("port") ?? 32400,
                                        local: c.bool("local") ?? false, relay: c.bool("relay") ?? false,
                                        ipv6: c.bool("IPv6") ?? false)
            }
            return PlexServer(id: id, name: r.str("name") ?? "Plex Media Server", sourceTitle: r.str("sourceTitle"),
                              owned: r.bool("owned") ?? false, accessToken: r.str("accessToken") ?? token,
                              connections: connections)
        }
    }

    /// Wie GetAllPossibleConnectionUrisForServer in pledo: direkte URIs, zusätzlich http://adresse:port, Relays separat.
    func candidateURIs(for server: PlexServer, relay: Bool) -> [String] {
        var result: [String] = []
        func add(_ s: String) { if !result.contains(s) { result.append(s) } }
        let conns = server.connections.filter { $0.relay == relay }
        for c in conns where c.local { add(c.uri) }
        for c in conns where !c.local { add(c.uri) }
        if !relay {
            for c in conns where !c.ipv6 && !c.address.isEmpty { add("http://\(c.address):\(c.port)") }
        }
        return result
    }

    func probe(_ uri: String, token: String, timeout: TimeInterval = 8) async -> Bool {
        guard let url = try? makeURL(uri, "/") else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        for (k, v) in headers(token: token) { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func race(_ uris: [String], token: String) async -> String? {
        if uris.isEmpty { return nil }
        return await withTaskGroup(of: String?.self) { group -> String? in
            for uri in uris {
                group.addTask { await self.probe(uri, token: token) ? uri : nil }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    /// Schnellste funktionierende Verbindung (GetUriFromFastestConnection in pledo).
    func fastestConnection(for server: PlexServer) async -> String? {
        if let uri = await race(candidateURIs(for: server, relay: false), token: server.accessToken) {
            return uri
        }
        return await race(candidateURIs(for: server, relay: true), token: server.accessToken)
    }

    // MARK: - Bibliotheken

    func libraries(server: PlexServer, uri: String) async throws -> [PlexLibrary] {
        let url = try makeURL(uri, "/library/sections")
        let json = try await requestJSON(url, token: server.accessToken) as? JSONObject
        let dirs = json?.obj("MediaContainer")?.arr("Directory") ?? []
        return dirs.compactMap { d -> PlexLibrary? in
            guard let key = d.str("key") else { return nil }
            return PlexLibrary(key: key, uuid: d.str("uuid"), name: d.str("title") ?? key,
                               type: d.str("type") ?? "", serverId: server.id)
        }
    }

    /// Seitenweises Laden (PlexLibraryIterator in pledo).
    func pagedMetadata(server: PlexServer, uri: String, path: String, query: [String: String],
                       batchSize: Int = 100, progress: ((Int, Int) -> Void)? = nil) async throws -> [JSONObject] {
        var all: [JSONObject] = []
        var start = 0
        var total = Int.max
        while start < total {
            try Task.checkCancellation()
            var q = query
            q["X-Plex-Container-Start"] = "\(start)"
            q["X-Plex-Container-Size"] = "\(batchSize)"
            let url = try makeURL(uri, path, query: q)
            let json = try await requestJSON(url, token: server.accessToken, timeout: 90) as? JSONObject
            let container: JSONObject = json?.obj("MediaContainer") ?? [:]
            let items = container.arr("Metadata")
            total = container.int("totalSize") ?? (start + items.count)
            all.append(contentsOf: items)
            progress?(all.count, total)
            if items.isEmpty { break }
            start += items.count
        }
        return all
    }

    static func mediaFiles(from m: JSONObject) -> [MediaFile] {
        var files: [MediaFile] = []
        for medium in m.arr("Media") {
            for part in medium.arr("Part") {
                guard let key = part.str("key") else { continue }
                files.append(MediaFile(
                    downloadUri: key,
                    serverFilePath: part.str("file") ?? "",
                    totalBytes: part.int64("size") ?? 0,
                    duration: medium.int64("duration") ?? part.int64("duration"),
                    bitrate: medium.int("bitrate"),
                    width: medium.int("width"),
                    height: medium.int("height"),
                    aspectRatio: medium.double("aspectRatio"),
                    audioChannels: medium.int("audioChannels"),
                    audioCodec: medium.str("audioCodec"),
                    videoCodec: medium.str("videoCodec"),
                    videoResolution: medium.str("videoResolution"),
                    container: part.str("container") ?? medium.str("container"),
                    videoFrameRate: medium.str("videoFrameRate"),
                    audioProfile: medium.str("audioProfile"),
                    videoProfile: medium.str("videoProfile")))
            }
        }
        return files
    }

    func movies(library: PlexLibrary, server: PlexServer, uri: String,
                progress: ((Int, Int) -> Void)? = nil) async throws -> [Movie] {
        let items = try await pagedMetadata(server: server, uri: uri, path: "/library/sections/\(library.key)/all",
                                            query: ["type": "1"], progress: progress)
        return items.compactMap { m -> Movie? in
            guard let rk = m.str("ratingKey") else { return nil }
            let files = Self.mediaFiles(from: m)
            guard !files.isEmpty else { return nil }
            return Movie(ratingKey: rk, key: m.str("key") ?? "", title: m.str("title") ?? "Unbekannt",
                         year: m.int("year"), summary: m.str("summary"), thumb: m.str("thumb"),
                         libraryId: library.id, serverId: server.id, mediaFiles: files)
        }
    }

    func shows(library: PlexLibrary, server: PlexServer, uri: String,
               progress: ((Int, Int) -> Void)? = nil) async throws -> [TvShow] {
        let items = try await pagedMetadata(server: server, uri: uri, path: "/library/sections/\(library.key)/all",
                                            query: ["type": "2"], progress: progress)
        return items.compactMap { m -> TvShow? in
            guard let rk = m.str("ratingKey") else { return nil }
            return TvShow(ratingKey: rk, key: m.str("key") ?? "", title: m.str("title") ?? "Unbekannt",
                          year: m.int("year"), summary: m.str("summary"), thumb: m.str("thumb"),
                          libraryId: library.id, serverId: server.id,
                          seasonCount: m.int("childCount"), episodeCount: m.int("leafCount"))
        }
    }

    func episodes(library: PlexLibrary, server: PlexServer, uri: String,
                  progress: ((Int, Int) -> Void)? = nil) async throws -> [Episode] {
        let items = try await pagedMetadata(server: server, uri: uri, path: "/library/sections/\(library.key)/all",
                                            query: ["type": "4"], batchSize: 200, progress: progress)
        return items.compactMap { m -> Episode? in
            guard let rk = m.str("ratingKey"), let showKey = m.str("grandparentRatingKey") else { return nil }
            let files = Self.mediaFiles(from: m)
            guard !files.isEmpty else { return nil }
            return Episode(ratingKey: rk, key: m.str("key") ?? "", title: m.str("title") ?? "Episode",
                           year: m.int("year"), thumb: m.str("thumb"), libraryId: library.id, serverId: server.id,
                           showRatingKey: showKey, showTitle: m.str("grandparentTitle") ?? "Serie",
                           seasonNumber: m.int("parentIndex") ?? 0, episodeNumber: m.int("index") ?? 0,
                           mediaFiles: files)
        }
    }

    func playlists(server: PlexServer, uri: String) async throws -> [Playlist] {
        let url = try makeURL(uri, "/playlists", query: ["playlistType": "video"])
        let json = try await requestJSON(url, token: server.accessToken) as? JSONObject
        let list = json?.obj("MediaContainer")?.arr("Metadata") ?? []
        var result: [Playlist] = []
        for p in list {
            guard let rk = p.str("ratingKey") else { continue }
            let itemsURL = try makeURL(uri, "/playlists/\(rk)/items")
            let itemsJSON = try? await requestJSON(itemsURL, token: server.accessToken, timeout: 60) as? JSONObject
            let items = (itemsJSON?.obj("MediaContainer")?.arr("Metadata") ?? []).compactMap { $0.str("ratingKey") }
            if items.isEmpty { continue }
            result.append(Playlist(ratingKey: rk, name: p.str("title") ?? "Playlist", serverId: server.id, items: items))
        }
        return result
    }

    // MARK: - Download & Bilder

    func downloadURL(base: String, partKey: String, token: String) throws -> URL {
        try makeURL(base, partKey, query: ["download": "1", "X-Plex-Token": token])
    }

    func thumbURL(base: String?, thumb: String?, token: String, width: Int = 240, height: Int = 360) -> URL? {
        guard let base, let thumb, !thumb.isEmpty else { return nil }
        return try? makeURL(base, "/photo/:/transcode",
                            query: ["width": "\(width)", "height": "\(height)", "minSize": "1", "upscale": "1",
                                    "url": thumb, "X-Plex-Token": token])
    }
}
