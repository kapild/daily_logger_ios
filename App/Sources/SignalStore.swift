import Foundation
import LoggerCore

/// The raw signal log, kept on the phone as a JSON file (a few dozen entries a
/// day). Signals older than 400 days are dropped. Calendar events are rebuilt
/// from it, so it is the source of truth for places.
final class SignalStore {
    static let shared = SignalStore()
    private let lock = NSLock()
    private let url: URL
    private var signals: [Signal] = []
    private var nextID: Int64 = 1

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("signals.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Signal].self, from: data) {
            signals = saved.sorted { ($0.ts, $0.id) < ($1.ts, $1.id) }
            nextID = (signals.map(\.id).max() ?? 0) + 1
        }
    }

    /// Logs a signal unless the rules say it adds nothing. Returns whether it was kept.
    @discardableResult
    func record(_ type: SignalType, place: Place? = nil, source: String, detail: String, at date: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let ts = Int64(date.timeIntervalSince1970 * 1000)
        let s = Signal(id: nextID, ts: ts, type: type, place: place?.rawValue, source: source, detail: detail)
        let history = signals.filter { $0.ts <= ts }
        guard SignalRules.shouldRecord(s, history: history) else { return false }
        nextID += 1
        signals.append(s)
        signals.sort { ($0.ts, $0.id) < ($1.ts, $1.id) }
        let cutoff = ts - 400 * 86_400_000
        signals.removeAll { $0.ts < cutoff }
        persist()
        return true
    }

    func between(_ from: Date, _ to: Date) -> [Signal] {
        lock.lock(); defer { lock.unlock() }
        let a = Int64(from.timeIntervalSince1970 * 1000), b = Int64(to.timeIntervalSince1970 * 1000)
        return signals.filter { $0.ts >= a && $0.ts <= b }
    }

    func all() -> [Signal] {
        lock.lock(); defer { lock.unlock() }
        return signals
    }

    func openRide(now: Date = Date()) -> Signal? {
        SignalRules.openRide(history: all(), now: Int64(now.timeIntervalSince1970 * 1000))
    }

    func delete(_ id: Int64) {
        lock.lock(); defer { lock.unlock() }
        signals.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(signals) { try? data.write(to: url, options: .atomic) }
    }
}
