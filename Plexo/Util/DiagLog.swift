import Foundation

/// Diagnose-Protokoll (threadsicher, letzte 800 Einträge) – zum Nachvollziehen,
/// welches Netzwerk wann verbunden, gewartet oder versagt hat.
enum DiagLog {
    private static let lock = NSLock()
    private static var lines: [String] = []
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func add(_ text: String) {
        lock.lock()
        lines.append("\(formatter.string(from: Date()))  \(text)")
        if lines.count > 800 { lines.removeFirst(lines.count - 800) }
        lock.unlock()
    }

    static func all() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    static func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }
}
