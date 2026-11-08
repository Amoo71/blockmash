import Foundation

// Erste Anfrage an den Server – entspricht download/probe.ts in Plexo:
// Größe, Range-Unterstützung, endgültige URL (nach Weiterleitungen), Dateiname, ETag.

struct ProbeResult: Sendable {
    let finalURL: URL
    let totalBytes: Int64
    let supportsRanges: Bool
    let fileName: String
    let etag: String?
    let lastModified: String?
}

enum Probe {
    static func run(url: URL, headers: [String: String]) async throws -> ProbeResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        var hasUA = false
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
            if k.lowercased() == "user-agent" { hasUA = true }
            if k.lowercased() == "cookie" { request.httpShouldHandleCookies = false }
        }
        if !hasUA { request.setValue(HTTPConnection.userAgent, forHTTPHeaderField: "User-Agent") }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        bytes.task.cancel()
        guard let http = response as? HTTPURLResponse else { throw HTTPError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw HTTPError.status(http.statusCode) }

        let finalURL = http.url ?? url
        var total: Int64 = 0
        var ranges = false
        if http.statusCode == 206, let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let slash = cr.lastIndex(of: "/"), let t = Int64(cr[cr.index(after: slash)...].trimmingCharacters(in: .whitespaces)) {
            total = t
            ranges = true
        } else if http.expectedContentLength > 0 {
            total = http.expectedContentLength
        }

        return ProbeResult(finalURL: finalURL, totalBytes: total, supportsRanges: ranges && total > 0,
                           fileName: fileName(response: http, url: finalURL, original: url),
                           etag: http.value(forHTTPHeaderField: "ETag"),
                           lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
    }

    static func fileName(response: HTTPURLResponse, url: URL, original: URL) -> String {
        if let cd = response.value(forHTTPHeaderField: "Content-Disposition"), let name = parseDisposition(cd) {
            return sanitize(name)
        }
        for u in [url, original] {
            let last = u.lastPathComponent.removingPercentEncoding ?? u.lastPathComponent
            if !last.isEmpty && last != "/" && last.contains(".") { return sanitize(last) }
        }
        if let suggested = response.suggestedFilename, !suggested.isEmpty, suggested != "Unknown" {
            return sanitize(suggested)
        }
        return "download"
    }

    static func parseDisposition(_ value: String) -> String? {
        let parts = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts where part.lowercased().hasPrefix("filename*=") {
            var v = String(part.dropFirst("filename*=".count))
            if let r = v.range(of: "''") { v = String(v[r.upperBound...]) }
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let decoded = v.removingPercentEncoding, !decoded.isEmpty { return decoded }
        }
        for part in parts where part.lowercased().hasPrefix("filename=") {
            let v = String(part.dropFirst("filename=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !v.isEmpty { return v }
        }
        return nil
    }

    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?*\"<>|")
        var r = ""
        r.unicodeScalars.append(contentsOf: name.unicodeScalars.filter {
            !invalid.contains($0) && !CharacterSet.controlCharacters.contains($0)
        })
        r = r.trimmingCharacters(in: .whitespacesAndNewlines)
        while r.hasPrefix(".") { r.removeFirst() }
        return r.isEmpty ? "download" : r
    }
}
