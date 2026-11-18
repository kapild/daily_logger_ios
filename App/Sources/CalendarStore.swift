import EventKit
import LoggerCore

/// Writes events with EventKit. Add your Google account under Settings >
/// Apps > Calendar > Calendar Accounts and the Logger calendar shows up here;
/// iOS syncs what's written back to Google.
final class CalendarStore {
    static let shared = CalendarStore()
    let store = EKEventStore()

    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter(\.allowsContentModifications).sorted { $0.title < $1.title }
    }

    func calendar(id: String?) -> EKCalendar? {
        guard let id else { return nil }
        return store.calendar(withIdentifier: id)
    }

    /// Our tagged events in `calendar` that start between the two dates.
    func tagged(in calendar: EKCalendar, from: Date, to: Date) -> [(ExistingEvent, EKEvent)] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        return store.events(matching: predicate).compactMap { e in
            guard let notes = e.notes, let tag = Format.tag(in: notes), e.startDate >= from else { return nil }
            let existing = ExistingEvent(
                id: e.eventIdentifier ?? UUID().uuidString, tag: tag,
                startMs: Int64(e.startDate.timeIntervalSince1970 * 1000),
                endMs: Int64(e.endDate.timeIntervalSince1970 * 1000),
                title: e.title ?? "", notes: notes)
            return (existing, e)
        }
    }

    /// Makes `calendar` match `desired` in the window; returns a one-line summary.
    func apply(_ desired: [DesiredEvent], to calendar: EKCalendar, from: Date, to: Date,
               isStale: (String) -> Bool, staleFrom: Date) throws -> String {
        let found = tagged(in: calendar, from: from, to: to)
        let desired = Reconcile.withoutOtherAppsCopies(desired, existing: found.map(\.0))
        let byID = Dictionary(found.map { ($0.0.id, $0.1) }, uniquingKeysWith: { a, _ in a })
        let plan = Reconcile.plan(
            desired: desired, existing: found.map(\.0),
            isStale: isStale, staleFromMs: Int64(staleFrom.timeIntervalSince1970 * 1000))
        for d in plan.inserts {
            let e = EKEvent(eventStore: store)
            e.calendar = calendar
            fill(e, d)
            try store.save(e, span: .thisEvent, commit: false)
        }
        for (id, d) in plan.updates {
            guard let e = byID[id] else { continue }
            fill(e, d)
            try store.save(e, span: .thisEvent, commit: false)
        }
        for id in plan.deletes {
            guard let e = byID[id] else { continue }
            try store.remove(e, span: .thisEvent, commit: false)
        }
        try store.commit()
        return plan.summary
    }

    private func fill(_ e: EKEvent, _ d: DesiredEvent) {
        e.title = d.title
        e.notes = d.notes
        e.isAllDay = d.allDay
        e.startDate = Date(timeIntervalSince1970: TimeInterval(d.startMs) / 1000)
        e.endDate = Date(timeIntervalSince1970: TimeInterval(d.endMs) / 1000)
        e.availability = .free
    }
}
