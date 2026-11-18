import Foundation

/// An event already in the calendar that carries one of our "[hc:...]" tags.
public struct ExistingEvent: Equatable, Sendable {
    public var id: String
    public var tag: String
    public var startMs: Int64
    public var endMs: Int64
    public var title: String
    public var notes: String

    public init(id: String, tag: String, startMs: Int64, endMs: Int64, title: String, notes: String) {
        self.id = id
        self.tag = tag
        self.startMs = startMs
        self.endMs = endMs
        self.title = title
        self.notes = notes
    }
}

/// What to change so the calendar matches the desired events.
public struct ReconcilePlan: Equatable, Sendable {
    public var inserts: [DesiredEvent] = []
    public var updates: [(id: String, event: DesiredEvent)] = []
    public var deletes: [String] = []
    public var unchanged = 0

    public static func == (a: ReconcilePlan, b: ReconcilePlan) -> Bool {
        a.inserts == b.inserts && a.deletes == b.deletes && a.unchanged == b.unchanged &&
            a.updates.map(\.id) == b.updates.map(\.id) && a.updates.map(\.event) == b.updates.map(\.event)
    }

    public var summary: String {
        "added \(inserts.count), fixed \(updates.count), removed \(deletes.count), \(unchanged) unchanged"
    }
}

/// Matches desired events to existing ones by tag, as the Android app does:
/// missing -> insert, different -> update, duplicates -> keep the first,
/// and (optionally) events whose tag `isStale` accepts that are no longer
/// wanted and start after `staleFromMs` -> delete.
public enum Reconcile {
    public static func plan(
        desired: [DesiredEvent],
        existing: [ExistingEvent],
        isStale: (String) -> Bool = { _ in false },
        staleFromMs: Int64 = .min
    ) -> ReconcilePlan {
        var plan = ReconcilePlan()
        let byTag = Dictionary(grouping: existing, by: \.tag)
        var seen = Set<String>()
        for want in desired where seen.insert(want.tag).inserted {
            let matches = (byTag[want.tag] ?? []).sorted { $0.id < $1.id }
            guard let keep = matches.first else {
                plan.inserts.append(want)
                continue
            }
            plan.deletes.append(contentsOf: matches.dropFirst().map(\.id))
            if same(keep, want) {
                plan.unchanged += 1
            } else {
                plan.updates.append((keep.id, want))
            }
        }
        for (tag, events) in byTag where isStale(tag) && !seen.contains(tag) {
            plan.deletes.append(contentsOf: events.filter { $0.startMs >= staleFromMs }.map(\.id))
        }
        return plan
    }

    /// Calendars keep whole seconds, so times are compared to the second.
    static func same(_ e: ExistingEvent, _ d: DesiredEvent) -> Bool {
        e.startMs / 1000 == d.startMs / 1000 && e.endMs / 1000 == d.endMs / 1000 &&
            e.title == d.title && normalize(e.notes) == normalize(d.notes)
    }

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops a sleep or workout this app would add when the Android app already
    /// wrote the same one (tags "sleep:<id>" / "ex:<id>" without "hk:") and it
    /// covers at least half of it, so a switch of phones doesn't double up nights.
    public static func withoutOtherAppsCopies(_ desired: [DesiredEvent], existing: [ExistingEvent]) -> [DesiredEvent] {
        let kinds = ["sleep:", "ex:"]
        return desired.filter { d in
            guard let kind = kinds.first(where: { d.tag.hasPrefix($0 + "hk:") }) else { return true }
            return !existing.contains { e in
                guard e.tag.hasPrefix(kind), !e.tag.hasPrefix(kind + "hk:") else { return false }
                let overlap = min(e.endMs, d.endMs) - max(e.startMs, d.startMs)
                let shorter = min(e.endMs - e.startMs, d.endMs - d.startMs)
                return shorter > 0 && overlap * 2 >= shorter
            }
        }
    }
}
