import Foundation

// Ein laufender Download – entspricht httpTransfer.ts, scheduler.ts und concurrency.ts in Plexo.
//
// - Die Datei ist in Blöcke geteilt (plan). Jeder Stream ist an ein Netzwerk gebunden und holt sich
//   den nächsten freien Block aus einer gemeinsamen Warteschlange: schnellere Netzwerke schaffen
//   so automatisch mehr Blöcke.
// - Jedes Netzwerk startet mit START_STREAMS und verdoppelt, sobald alle Streams Daten bekommen,
//   bis MAX_STREAMS. Lehnt der Server Verbindungen ab (429/503/403), sinkt das Limit und steigt nach
//   einer Minute wieder um eins.
// - Gegen Ende rennen freie Streams langsamen Blöcken hinterher („Hedge“): wer zuerst fertig ist,
//   gewinnt.
// - Fortschritt pro Block ist die zusammenhängende „Front“ ab Blockanfang – Pause und Neustart
//   setzen genau dort fort.

enum DownloadPlan {
    static let mib: Int64 = 1024 * 1024
    static let maxBlock: Int64 = 8 * mib
    static let minBlock: Int64 = mib
    static let startStreams = 4
    static let maxStreams = 16
    static let blocksPerStream: Int64 = 2

    static func blocks(totalBytes: Int64, splittable: Bool, networkCount: Int) -> [BlockState] {
        guard splittable, totalBytes > 0 else {
            return [BlockState(start: 0, end: totalBytes > 0 ? totalBytes : -1)]
        }
        let target = Int64(max(1, networkCount)) * Int64(maxStreams) * blocksPerStream
        let size = min(max((totalBytes + target - 1) / target, minBlock), maxBlock)
        var result: [BlockState] = []
        var start: Int64 = 0
        while start < totalBytes {
            let end = min(start + size, totalBytes)
            result.append(BlockState(start: start, end: end))
            start = end
        }
        return result
    }
}

enum JobEvent: Sendable {
    case progress(blocks: [BlockState], bytesByNetwork: [String: Int64], live: DownloadLive, usage: [NetworkKind: Int64])
    case finished(totalBytes: Int64, blocks: [BlockState], bytesByNetwork: [String: Int64])
    case failed(String, blocks: [BlockState], bytesByNetwork: [String: Int64])
}

actor DownloadJob {
    typealias Handler = @Sendable (JobEvent) -> Void

    struct Work: Sendable {
        let attempt: Int
        let offset: Int64
        let end: Int64
    }

    enum Claim: Sendable {
        case stop
        case wait
        case work(Work)
    }

    enum Decision: Sendable {
        case retry
        case retire
    }

    private struct Attempt {
        let block: Int
        let offset: Int64
        let network: NetworkKind
        let startedAt: Date
        let hedge: Bool
        var received: Int64 = 0
        var cancelled = false
    }

    private struct StreamInfo {
        let kind: NetworkKind
        let task: Task<Void, Never>
    }

    nonisolated let id: UUID
    nonisolated let fd: Int32
    private let url: URL
    private let headers: [String: String]
    private let splittable: Bool
    private let fixedStreams: Int
    private let handler: Handler

    private var blocks: [BlockState]
    private var totalBytes: Int64
    private var enabled: Set<NetworkKind>
    private var usable: Set<NetworkKind>
    private var bytesByNetwork: [String: Int64]

    private var attempts: [Int: Attempt] = [:]
    private var streams: [Int: StreamInfo] = [:]
    private var stopping: Set<Int> = []
    private var answered: Set<Int> = []
    private var retire: [NetworkKind: Int] = [:]
    private var ceilings: [NetworkKind: (limit: Int, since: Date)] = [:]
    private var failures: [NetworkKind: Int] = [:]
    private var failedNetworks: Set<NetworkKind> = []
    private var hedges: [Int: Int] = [:]
    private var tickBytes: [NetworkKind: Int64] = [:]
    private var speeds: [NetworkKind: Double] = [:]
    private var lastTick = Date()
    private var lastError: String?
    private var nextId = 1
    private var stopped = false
    private var supervisor: Task<Void, Never>?

    init(record: DownloadRecord, url: URL, fd: Int32, enabled: Set<NetworkKind>, usable: Set<NetworkKind>,
         handler: @escaping Handler) {
        self.id = record.id
        self.fd = fd
        self.url = url
        self.headers = record.headers
        self.splittable = record.supportsRanges && record.totalBytes > 0
        self.fixedStreams = record.streams
        self.handler = handler
        self.blocks = record.blocks
        self.totalBytes = record.totalBytes
        self.enabled = enabled
        self.usable = usable
        self.bytesByNetwork = record.bytesByNetwork
    }

    // MARK: - Steuerung von außen

    func start() {
        supervisor = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, await self.tick() else { break }
            }
        }
        if allComplete {
            finish()
        } else {
            reconcile()
        }
    }

    func setEnabled(_ kind: NetworkKind, _ on: Bool) {
        if on {
            enabled.insert(kind)
            failedNetworks.remove(kind)
            failures[kind] = 0
        } else {
            enabled.remove(kind)
        }
        reconcile()
    }

    func setUsable(_ kinds: Set<NetworkKind>) {
        for k in kinds.subtracting(usable) {
            failedNetworks.remove(k)
            failures[k] = 0
        }
        usable = kinds
        reconcile()
    }

    /// Pause/Entfernen: Streams anhalten, Datei schließen, Stand zurückgeben.
    func stop() async -> (blocks: [BlockState], bytesByNetwork: [String: Int64]) {
        if !stopped {
            stopped = true
            await shutdown(truncate: false)
        }
        return (blocks, bytesByNetwork)
    }

    // MARK: - Takt (jede Sekunde)

    private func tick() -> Bool {
        guard !stopped else { return false }
        let now = Date()
        let dt = max(0.2, now.timeIntervalSince(lastTick))
        lastTick = now
        for kind in NetworkKind.allCases {
            let current = Double(tickBytes[kind] ?? 0) / dt
            speeds[kind] = (speeds[kind] ?? current) * 0.4 + current * 0.6
        }
        let usage = tickBytes
        tickBytes = [:]
        reconcile()
        handler(.progress(blocks: blocks, bytesByNetwork: bytesByNetwork, live: makeLive(), usage: usage))
        return true
    }

    private func makeLive() -> DownloadLive {
        var nets: [NetworkKind: NetworkLive] = [:]
        for kind in NetworkKind.allCases {
            nets[kind] = NetworkLive(speed: speeds[kind] ?? 0, streams: streamCount(kind),
                                     bytes: bytesByNetwork[kind.rawValue] ?? 0,
                                     failing: failedNetworks.contains(kind))
        }
        var live = DownloadLive()
        live.networks = nets
        live.speed = nets.values.reduce(0) { $0 + $1.speed }
        live.activeBlocks = Set(attempts.values.filter { !$0.cancelled }.map(\.block))
        let possible = enabled.intersection(usable).subtracting(failedNetworks)
        if possible.isEmpty {
            live.message = enabled.isEmpty ? "Alle Netzwerke für diesen Download ausgeschaltet"
                : "Kein ausgewähltes Netzwerk verfügbar – wartet"
        } else if let lastError, streams.isEmpty {
            live.message = lastError
        }
        return live
    }

    // MARK: - Streams pro Netzwerk

    private var allComplete: Bool { blocks.allSatisfy(\.isComplete) }

    private func streamCount(_ kind: NetworkKind) -> Int {
        streams.filter { $0.value.kind == kind && !stopping.contains($0.key) }.count
    }

    private func isAllowed(_ kind: NetworkKind) -> Bool {
        enabled.contains(kind) && usable.contains(kind) && !failedNetworks.contains(kind)
    }

    /// Ohne Range-Unterstützung: genau ein Stream auf dem besten erlaubten Netzwerk.
    private var singleStreamKind: NetworkKind? {
        [NetworkKind.ethernet, .wifi, .cellular].first { isAllowed($0) }
    }

    private func desiredStreams(_ kind: NetworkKind, current: Int) -> Int {
        guard isAllowed(kind) else { return 0 }
        if !splittable { return kind == singleStreamKind ? 1 : 0 }
        let cap = min(DownloadPlan.maxStreams, ceilings[kind]?.limit ?? Int.max)
        if fixedStreams > 0 { return min(fixedStreams, cap) }
        if current == 0 { return min(DownloadPlan.startStreams, cap) }
        let mine = streams.filter { $0.value.kind == kind && !stopping.contains($0.key) }.map(\.key)
        let allAnswered = mine.allSatisfy { answered.contains($0) }
        return allAnswered ? min(current * 2, cap) : min(current, cap)
    }

    private func reconcile() {
        guard !stopped else { return }
        let now = Date()
        for (kind, c) in ceilings where now.timeIntervalSince(c.since) >= 60 {
            if c.limit + 1 >= DownloadPlan.maxStreams {
                ceilings[kind] = nil
            } else {
                ceilings[kind] = (c.limit + 1, now)
            }
        }
        let incomplete = blocks.filter { !$0.isComplete }.count
        var totalStreams = streams.count - stopping.count
        for kind in NetworkKind.allCases {
            if !isAllowed(kind) {
                for (sid, s) in streams where s.kind == kind && !stopping.contains(sid) {
                    stopping.insert(sid)
                    s.task.cancel()
                }
                retire[kind] = 0
                continue
            }
            let current = streamCount(kind) - (retire[kind] ?? 0)
            let target = desiredStreams(kind, current: current)
            if current < target {
                let spare = max(incomplete - totalStreams, current == 0 ? 1 : 0)
                let add = min(target - current, spare)
                if add > 0 {
                    for _ in 0..<add { spawn(kind) }
                    totalStreams += add
                }
            } else if current > target {
                retire[kind, default: 0] += current - target
            }
        }
    }

    private func spawn(_ kind: NetworkKind) {
        let sid = nextId
        nextId += 1
        let task = Task { [weak self] () -> Void in
            guard let self else { return }
            await self.runStream(id: sid, kind: kind)
        }
        streams[sid] = StreamInfo(kind: kind, task: task)
    }

    // MARK: - Arbeit verteilen

    private func attemptsOn(_ block: Int) -> [Attempt] {
        attempts.values.filter { $0.block == block && !$0.cancelled }
    }

    private func claimWork(stream sid: Int, kind: NetworkKind) -> Claim {
        if stopped || stopping.contains(sid) { return .stop }
        if let r = retire[kind], r > 0 {
            retire[kind] = r - 1
            stopping.insert(sid)
            return .stop
        }
        guard isAllowed(kind) else {
            stopping.insert(sid)
            return .stop
        }
        if allComplete { return .stop }
        for i in blocks.indices where !blocks[i].isComplete && attemptsOn(i).isEmpty {
            if !splittable {
                blocks[i].done = 0
                blocks[i].byNetwork = [:]
            }
            return .work(newAttempt(i, kind: kind, hedge: false))
        }
        if splittable, let i = hedgeCandidate(for: kind) {
            hedges[i, default: 0] += 1
            return .work(newAttempt(i, kind: kind, hedge: true))
        }
        return .wait
    }

    private func newAttempt(_ i: Int, kind: NetworkKind, hedge: Bool) -> Work {
        let id = nextId
        nextId += 1
        let b = blocks[i]
        let offset = b.start + b.done
        attempts[id] = Attempt(block: i, offset: offset, network: kind, startedAt: Date(), hedge: hedge)
        return Work(attempt: id, offset: offset, end: b.end)
    }

    /// Ein Block, dessen laufender Versuch deutlich länger brauchen wird als ein neuer.
    private func hedgeCandidate(for kind: NetworkKind) -> Int? {
        let now = Date()
        let streamsHere = max(1, streamCount(kind))
        let mySpeed = (speeds[kind] ?? 0) / Double(streamsHere)
        var best: (index: Int, eta: Double)?
        for (i, b) in blocks.enumerated() where !b.isComplete {
            let running = attemptsOn(i)
            guard running.count == 1, (hedges[i] ?? 0) < 2, let length = b.length else { continue }
            let a = running[0]
            let remaining = Double(length - b.done)
            guard remaining > 256 * 1024 else { continue }
            let age = now.timeIntervalSince(a.startedAt)
            guard age > 3 else { continue }
            let speed = Double(a.received) / age
            let eta = speed > 0 ? remaining / speed : .infinity
            let myEta = 1.5 + (mySpeed > 0 ? remaining / mySpeed : 15)
            if eta > myEta * 1.5, best == nil || eta > best!.eta {
                best = (i, eta)
            }
        }
        return best?.index
    }

    private func markAnswered(_ sid: Int) {
        answered.insert(sid)
    }

    private func received(attempt id: Int, bytes: Int64) -> Bool {
        guard var a = attempts[id], !a.cancelled, !stopped else { return false }
        a.received += bytes
        attempts[id] = a
        let kind = a.network
        tickBytes[kind, default: 0] += bytes
        bytesByNetwork[kind.rawValue, default: 0] += bytes
        failures[kind] = 0
        var b = blocks[a.block]
        b.byNetwork[kind.rawValue, default: 0] += bytes
        let front = a.offset - b.start + a.received
        if front > b.done {
            b.done = b.length.map { min($0, front) } ?? front
        }
        blocks[a.block] = b
        if b.isComplete { completeBlock(a.block) }
        return true
    }

    private func completeBlock(_ i: Int) {
        for (id, a) in attempts where a.block == i {
            attempts[id]?.cancelled = true
        }
        if allComplete { finish() }
    }

    private func finishAttempt(_ id: Int) {
        guard let a = attempts.removeValue(forKey: id) else { return }
        if blocks[a.block].end < 0 && !a.cancelled {
            // Unbekannte Größe: das Ende der Antwort ist das Dateiende.
            let total = blocks[a.block].start + a.received
            blocks[a.block].end = total
            blocks[a.block].done = a.received
            totalBytes = total
        }
        if allComplete { finish() }
    }

    private func release(_ id: Int) {
        attempts.removeValue(forKey: id)
    }

    private func attemptFailed(_ id: Int, kind: NetworkKind, stream sid: Int, error: Error) -> Decision {
        attempts.removeValue(forKey: id)
        if stopped { return .retire }
        lastError = error.localizedDescription

        if let posix = error as? POSIXError, posix.code == .ENOSPC {
            fail("Kein Speicherplatz mehr frei")
            return .retire
        }
        if let h = error as? HTTPError {
            if h.isRefusal {
                let mine = streams.filter { $0.value.kind == kind && !stopping.contains($0.key) }.map(\.key)
                let othersServing = mine.contains { $0 != sid && answered.contains($0) }
                if mine.count > 1 && othersServing {
                    ceilings[kind] = (max(1, mine.count - 1), Date())
                    stopping.insert(sid)
                    return .retire
                }
            }
            if case .rangeIgnored = h {
                fail("Der Server unterstützt keine Teil-Downloads mehr. Bitte erneut starten.")
                return .retire
            }
            if case .status(let code) = h, [401, 404, 410].contains(code) {
                failures[kind, default: 0] += 4
            }
        }
        failures[kind, default: 0] += 1
        if (failures[kind] ?? 0) >= 12 {
            failedNetworks.insert(kind)
            stopping.insert(sid)
            let left = enabled.intersection(usable).subtracting(failedNetworks)
            if left.isEmpty && attempts.isEmpty {
                fail(error.localizedDescription + " – Link evtl. abgelaufen? „Link ersetzen“ behält den Fortschritt.")
            }
            return .retire
        }
        return .retry
    }

    private func streamEnded(_ sid: Int) {
        streams.removeValue(forKey: sid)
        stopping.remove(sid)
        answered.remove(sid)
    }

    // MARK: - Ende

    private func finish() {
        guard !stopped else { return }
        stopped = true
        let total = totalBytes
        Task {
            await self.shutdown(truncate: true)
            let snapshot = await self.snapshot()
            self.handler(.finished(totalBytes: total, blocks: snapshot.0, bytesByNetwork: snapshot.1))
        }
    }

    private func fail(_ message: String) {
        guard !stopped else { return }
        stopped = true
        Task {
            await self.shutdown(truncate: false)
            let snapshot = await self.snapshot()
            self.handler(.failed(message, blocks: snapshot.0, bytesByNetwork: snapshot.1))
        }
    }

    private func snapshot() -> ([BlockState], [String: Int64]) { (blocks, bytesByNetwork) }

    private var closed = false

    /// Wartet, bis alle Streams beendet sind, und schließt erst dann die Datei.
    private func shutdown(truncate: Bool) async {
        supervisor?.cancel()
        let tasks = streams.values.map(\.task)
        for t in tasks { t.cancel() }
        for t in tasks { await t.value }
        guard !closed else { return }
        closed = true
        if truncate && totalBytes > 0 { ftruncate(fd, off_t(totalBytes)) }
        fsync(fd)
        close(fd)
    }

    // MARK: - Ein Stream (läuft außerhalb des Actors)

    nonisolated private func runStream(id sid: Int, kind: NetworkKind) async {
        var connection: HTTPConnection?
        var currentURL = url
        var backoff: Double = 1
        defer { connection?.cancel() }

        loop: while !Task.isCancelled {
            let claim = await claimWork(stream: sid, kind: kind)
            let work: Work
            switch claim {
            case .stop:
                break loop
            case .wait:
                try? await Task.sleep(nanoseconds: 700_000_000)
                continue loop
            case .work(let w):
                work = w
            }

            do {
                let conn: HTTPConnection
                if let c = connection, c.isReusable, c.matches(currentURL) {
                    conn = c
                } else {
                    connection?.cancel()
                    conn = try HTTPConnection(url: currentURL, kind: kind)
                    connection = conn
                    try await conn.start()
                }
                let ranged = splittable
                let head = try await conn.request(currentURL, headers: headers,
                                                  rangeStart: ranged ? work.offset : nil,
                                                  rangeEnd: ranged && work.end >= 0 ? work.end - 1 : nil)
                guard (200..<300).contains(head.status) else { throw HTTPError.status(head.status) }
                if ranged {
                    if head.status != 206 { throw HTTPError.rangeIgnored }
                    if let s = head.contentRangeStart, s != work.offset { throw HTTPError.badResponse }
                }
                await markAnswered(sid)
                var position = work.offset
                let fd = self.fd
                try await conn.readBody(head) { data in
                    try DownloadJob.write(fd: fd, data: data, at: position)
                    position += Int64(data.count)
                    let delay = await RateLimiter.shared.delay(for: data.count, kind: kind)
                    if delay > 0 {
                        try await Task.sleep(nanoseconds: UInt64(min(delay, 5) * 1_000_000_000))
                    }
                    return await self.received(attempt: work.attempt, bytes: Int64(data.count))
                }
                await finishAttempt(work.attempt)
                backoff = 1
            } catch HTTPError.redirect(let next) {
                connection?.cancel()
                connection = nil
                currentURL = next
                await release(work.attempt)
            } catch {
                connection?.cancel()
                connection = nil
                if Task.isCancelled || error is CancellationError {
                    await release(work.attempt)
                    break loop
                }
                let decision = await attemptFailed(work.attempt, kind: kind, stream: sid, error: error)
                if case .retire = decision { break loop }
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff = min(backoff * 2, 30)
            }
        }
        await streamEnded(sid)
    }

    nonisolated static func write(fd: Int32, data: Data, at offset: Int64) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard var base = raw.baseAddress else { return }
            var remaining = raw.count
            var off = offset
            while remaining > 0 {
                let n = pwrite(fd, base, remaining, off_t(off))
                if n < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                remaining -= n
                off += Int64(n)
                base = base.advanced(by: n)
            }
        }
    }
}
