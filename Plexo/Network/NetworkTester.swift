import Foundation

// Verbindungstest pro Netzwerk: lädt bis zu 8 s eine Testdatei über genau dieses Netzwerk.
// Zeigt, ob z. B. Mobilfunk wirklich genutzt werden kann (oder warum nicht).

enum NetworkTester {
    static let testURL = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!

    static func run(_ kind: NetworkKind) async -> String {
        let start = Date()
        var received: Int64 = 0
        do {
            let conn = try HTTPConnection(url: testURL, kind: kind)
            defer { conn.cancel() }
            try await conn.start(timeout: 15)
            let connected = Date().timeIntervalSince(start)
            let head = try await conn.request(testURL, headers: [:], rangeStart: nil, rangeEnd: nil)
            guard (200..<300).contains(head.status) else { return "❌ HTTP \(head.status)" }
            let bodyStart = Date()
            try await conn.readBody(head) { data in
                received += Int64(data.count)
                return Date().timeIntervalSince(bodyStart) < 8
            }
            let seconds = max(0.1, Date().timeIntervalSince(bodyStart))
            let speed = Double(received) / seconds
            return "✅ \(Format.speed(speed)) · Verbindung in \(Int(connected * 1000)) ms"
        } catch {
            if received > 0 {
                let seconds = max(0.1, Date().timeIntervalSince(start))
                return "✅ \(Format.speed(Double(received) / seconds))"
            }
            var text = "❌ \(error.localizedDescription)"
            if kind == .cellular {
                text += "\nPrüfe: iOS-Einstellungen › Mobilfunk › LiveContainer (bzw. Plexo) muss an sein."
            }
            return text
        }
    }
}
