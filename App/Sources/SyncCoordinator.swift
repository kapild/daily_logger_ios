import EventKit
import Foundation
import LoggerCore

/// Rebuilds calendar events from Apple Health and the signal log. One run at
/// a time; every run is safe to repeat (events are matched by tag).
actor SyncCoordinator {
    static let shared = SyncCoordinator()
    private static let day: TimeInterval = 86_400

    /// Everything: health, then places.
    @discardableResult
    func syncAll(reason: String) async -> String {
        let health = await syncHealthLocked()
        let places = await syncPlacesLocked()
        return finish(reason, [health, places])
    }

    @discardableResult
    func syncHealth(reason: String) async -> String {
        finish(reason, [await syncHealthLocked()])
    }

    @discardableResult
    func syncPlaces(reason: String) async -> String {
        finish(reason, [await syncPlacesLocked()])
    }

    private func finish(_ reason: String, _ parts: [String]) -> String {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let line = "\(time) · \(reason)\n" + parts.joined(separator: "\n")
        Settings.shared.lastSync = line
        SyncLog.append(line)
        return line
    }

    private func calendar() -> (CalendarStore, EKCalendar)? {
        let cal = CalendarStore.shared
        guard cal.authorized, let c = cal.calendar(id: Settings.shared.calendarID) else { return nil }
        return (cal, c)
    }

    /// Sleep and workouts from the last 7 days.
    private func syncHealthLocked() async -> String {
        let s = Settings.shared
        guard s.logSleep || s.logWorkouts else { return "Health: off." }
        guard HealthSource.shared.available else { return "Health: not available on this device." }
        guard let target = calendar() else { return "Health: choose a calendar in Setup." }
        let (cal, calendar) = target
        let now = Date()
        let from = now.addingTimeInterval(-7 * Self.day)
        let tz = TimeZone.current
        do {
            var desired: [DesiredEvent] = []
            var counts: [String] = []
            if s.logSleep {
                let sessions = SleepBuilder.sessions(try await HealthSource.shared.sleepSamples(from: from, to: now))
                    .filter { $0.end <= Int64(now.timeIntervalSince1970 * 1000) }
                desired += sessions.map { SleepBuilder.event($0, tz: tz) }
                counts.append("\(sessions.count) sleep")
            }
            if s.logWorkouts {
                let workouts = try await HealthSource.shared.workouts(from: from, to: now)
                desired += workouts.map { WorkoutBuilder.event($0, tz: tz) }
                counts.append("\(workouts.count) workouts")
            }
            let summary = try cal.apply(
                desired, to: calendar,
                from: from.addingTimeInterval(-2 * Self.day), to: now.addingTimeInterval(Self.day),
                isStale: { _ in false }, staleFrom: from)
            return "Health: \(counts.joined(separator: ", ")); \(summary)."
        } catch {
            return "Health: \(error.localizedDescription)"
        }
    }

    /// Places, drives and commutes from the last 2 days of signals.
    private func syncPlacesLocked() async -> String {
        let s = Settings.shared
        guard s.logPlaces else { return "Places: off." }
        await MotionDrives.check()
        guard let target = calendar() else { return "Places: choose a calendar in Setup." }
        let (cal, calendar) = target
        let now = Date()
        let from = now.addingTimeInterval(-2 * Self.day)
        let signalsFrom = from.addingTimeInterval(-3 * Self.day)
        let signals = SignalRules.clean(SignalStore.shared.between(signalsFrom, now))
        let timeline = PlaceTimeline.build(signals, geofenced: s.geofenced)
        let desired = PlacesBuilder.build(timeline, now: Int64(now.timeIntervalSince1970 * 1000), tz: .current)
        do {
            let summary = try cal.apply(
                desired, to: calendar,
                from: signalsFrom.addingTimeInterval(-Self.day), to: now.addingTimeInterval(Self.day),
                isStale: PlacesBuilder.isOwnTag, staleFrom: from)
            return "Places: \(signals.count) signals; \(summary)."
        } catch {
            return "Places: \(error.localizedDescription)"
        }
    }
}


/// The last few sync results, for the Activity screen.
enum SyncLog {
    private static let key = "syncLog"

    static func append(_ line: String) {
        var lines = all()
        lines.insert(line, at: 0)
        UserDefaults.standard.set(Array(lines.prefix(50)), forKey: key)
    }

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}
