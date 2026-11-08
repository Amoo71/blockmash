import Foundation

// Geschwindigkeitslimits – entspricht network/limits.ts in Plexo (global und pro Netzwerk).
// Token-Bucket: jeder Stream "bezahlt" empfangene Bytes und wartet, wenn das Budget leer ist.

actor RateLimiter {
    static let shared = RateLimiter()

    private struct Bucket {
        var rate: Double = 0
        var tokens: Double = 0
        var last = Date()

        mutating func reserve(_ bytes: Double, now: Date) -> TimeInterval {
            guard rate > 0 else { return 0 }
            tokens = min(rate, tokens + now.timeIntervalSince(last) * rate)
            last = now
            tokens -= bytes
            return tokens < 0 ? -tokens / rate : 0
        }
    }

    private var global = Bucket()
    private var perNetwork: [NetworkKind: Bucket] = [:]

    func setLimits(global globalRate: Int64, perNetwork rates: [NetworkKind: Int64]) {
        if Double(globalRate) != global.rate {
            global = Bucket(rate: Double(globalRate), tokens: Double(globalRate), last: Date())
        }
        for kind in NetworkKind.allCases {
            let r = Double(rates[kind] ?? 0)
            if perNetwork[kind]?.rate != r {
                perNetwork[kind] = Bucket(rate: r, tokens: r, last: Date())
            }
        }
    }

    /// Wie lange der Aufrufer warten muss, nachdem er `bytes` empfangen hat.
    func delay(for bytes: Int, kind: NetworkKind) -> TimeInterval {
        let now = Date()
        let a = global.reserve(Double(bytes), now: now)
        var b: TimeInterval = 0
        if var bucket = perNetwork[kind] {
            b = bucket.reserve(Double(bytes), now: now)
            perNetwork[kind] = bucket
        }
        return max(a, b)
    }
}
