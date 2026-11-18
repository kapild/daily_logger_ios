import Foundation

/// Turns a `Timeline` into calendar events, with the Android app's titles:
///  - "Left home | At: 8:02 am", "Arrived office | At: 9:01 am"
///  - "At work | Dur: 8 hours 39 mins | Start: 9:01 am End: 5:40 pm", and "Gym | ..."
///  - "Commute to work by car | Dur: 52 mins | ..."
///  - By shuttle, overlapping events: the door-to-door trip ("Work to home via
///    shuttle and car"), the ride ("Commute home by shuttle"), and any drive
///    to or from the stop ("Drive | ...")
///  - "Drive | Dur: 23 mins | ..." for car trips that aren't a commute
/// Tags are "pl:<kind>:i<signal id>"; the "i" keeps them apart from the
/// Android app's numbers in the same calendar.
public enum PlacesBuilder {
    public static let tagRoot = "pl:"

    /// Places events this app wrote ("pl:trip:i12"). The Android app's
    /// ("pl:trip:82") are never removed from here.
    public static func isOwnTag(_ tag: String) -> Bool {
        tag.hasPrefix(tagRoot) && tag.split(separator: ":").last?.hasPrefix("i") == true
    }
    static let markerMs: Int64 = 60_000

    public static func build(_ t: Timeline, now: Int64, tz: TimeZone) -> [DesiredEvent] {
        var out: [DesiredEvent] = []
        let clock = { (ms: Int64) in Format.clock(ms, tz) }

        for (index, v) in t.visits.enumerated() {
            let name = v.place.label.lowercased()
            if v.place.markers && v.startKnown {
                out.append(marker("Arrived \(name)", v.start, how(v.startSource, v.startDetail), "\(tagRoot)arrive:i\(v.startId)", tz))
            }
            guard let end = v.end else { continue }
            // A fresh exit might be undone by a quick return; wait before writing it.
            if index == t.visits.count - 1 && now - end <= PlaceTimeline.flapMs { continue }
            if v.place.markers && v.endKnown {
                out.append(marker("Left \(name)", end, how(v.endSource, v.endDetail), "\(tagRoot)leave:i\(v.endId)", tz))
            }
            if let span = v.place.spanTitle, v.startKnown, end - v.start >= PlaceTimeline.minStayMs {
                let tag = "\(tagRoot)stay:i\(v.startId)"
                let ending = v.endKnown
                    ? "left \(clock(end))"
                    : "exit not detected, so this ends when you arrived at \(v.endDetail.lowercased()) (\(clock(end)))"
                out.append(DesiredEvent(
                    tag: tag, startMs: v.start, endMs: end,
                    title: Format.spanTitle(span, minutes: Format.minutes(end - v.start), start: v.start, end: end, tz),
                    notes: "Arrived \(clock(v.start)), \(ending)\n\n\(tagPrefix)\(tag)]"))
            }
        }

        var ridesInTrips = Set<ShuttleRide>()
        var shuttleTrips: [Trip] = []
        for trip in t.trips {
            let legs = t.drives.filter { $0.start < trip.end && $0.end > trip.start }
            let driveMs = legs.reduce(Int64(0)) { $0 + min($1.end, trip.end) - max($1.start, trip.start) }
            let mostlyCar = driveMs * 10 >= (trip.end - trip.start) * 6
            let rides = t.rides.filter { $0.start < trip.end && $0.end > trip.start }
            let byShuttle = !rides.isEmpty || t.shuttleTimes.contains { $0 >= trip.start && $0 <= trip.end }
            let mode: String? = byShuttle && !legs.isEmpty ? "shuttle and car" : byShuttle ? "shuttle" : mostlyCar ? "car" : nil
            out.append(tripEvent(trip, mode: mode, byShuttle: byShuttle, legs: legs, rides: rides, tz))
            for r in rides { out.append(rideEvent(r, trip: trip, tz)) }
            ridesInTrips.formUnion(rides)
            if byShuttle { shuttleTrips.append(trip) }
        }
        for r in t.rides where !ridesInTrips.contains(r) { out.append(rideEvent(r, trip: nil, tz)) }
        // A drive inside a car commute is that commute; a drive inside a shuttle
        // trip (to or from the stop) gets its own event.
        for d in t.drives {
            let overlaps = t.trips.filter { d.start < $0.end && d.end > $0.start }
            if overlaps.isEmpty || overlaps.contains(where: { shuttleTrips.contains($0) }) {
                let tag = "\(tagRoot)drive:i\(d.id)"
                out.append(DesiredEvent(
                    tag: tag, startMs: d.start, endMs: d.end,
                    title: Format.spanTitle("Drive", minutes: Format.minutes(d.end - d.start), start: d.start, end: d.end, tz),
                    notes: "Car connected \(clock(d.start)), disconnected \(clock(d.end))\nCar: \(d.device)\n\n\(tagPrefix)\(tag)]"))
            }
        }
        return out
    }

    private static func marker(_ title: String, _ ts: Int64, _ how: String, _ tag: String, _ tz: TimeZone) -> DesiredEvent {
        DesiredEvent(
            tag: tag, startMs: ts, endMs: ts + markerMs,
            title: Format.markerTitle(title, at: ts, tz),
            notes: "\(title) at \(Format.clock(ts, tz))\nDetected by: \(how)\n\n\(tagPrefix)\(tag)]")
    }

    private static func base(_ t: Trip, home: String, work: String) -> String {
        if t.from == .home && t.to == .office { return home }
        if t.from == .office && t.to == .home { return work }
        return "\(t.from.label) to \(t.to.label.lowercased())"
    }

    private static func tripEvent(_ t: Trip, mode: String?, byShuttle: Bool, legs: [Drive], rides: [ShuttleRide], _ tz: TimeZone) -> DesiredEvent {
        let tag = "\(tagRoot)trip:i\(t.id)"
        let title: String
        if byShuttle {
            title = "\(base(t, home: "Home to work", work: "Work to home")) via \(mode ?? "shuttle")"
        } else {
            let b = base(t, home: "Commute to work", work: "Commute home")
            title = mode.map { "\(b) by \($0)" } ?? b
        }
        let rideLines = rides.map { r in
            "\nShuttle: \(Format.clock(r.start, tz)) – \(Format.clock(r.end, tz)) (\(Format.dur(minutes: Format.minutes(r.end - r.start))))"
        }.joined()
        let driveLines = legs.map { d in
            "\nDrive: \(Format.clock(d.start, tz)) – \(Format.clock(d.end, tz)) (\(Format.dur(minutes: Format.minutes(d.end - d.start))), \(d.device))"
        }.joined()
        return DesiredEvent(
            tag: tag, startMs: t.start, endMs: t.end,
            title: Format.spanTitle(title, minutes: Format.minutes(t.end - t.start), start: t.start, end: t.end, tz),
            notes: "Left \(t.from.label.lowercased()) \(Format.clock(t.start, tz)), arrived \(t.to.label.lowercased()) \(Format.clock(t.end, tz))\(rideLines)\(driveLines)\n\n\(tagPrefix)\(tag)]")
    }

    private static func rideEvent(_ r: ShuttleRide, trip: Trip?, _ tz: TimeZone) -> DesiredEvent {
        let tag = "\(tagRoot)ride:i\(r.id)"
        let title: String
        if let trip, trip.from == .home && trip.to == .office {
            title = "Commute to work by shuttle"
        } else if let trip, trip.from == .office && trip.to == .home {
            title = "Commute home by shuttle"
        } else {
            title = "Shuttle ride"
        }
        let whole = trip.map { t in
            "\nWhole trip: left \(t.from.label.lowercased()) \(Format.clock(t.start, tz)), arrived \(t.to.label.lowercased()) \(Format.clock(t.end, tz)) (\(Format.dur(minutes: Format.minutes(t.end - t.start))))"
        } ?? ""
        let off = r.endSource == "bluetooth" ? "car connected \(Format.clock(r.end, tz))" : "left it \(Format.clock(r.end, tz))"
        return DesiredEvent(
            tag: tag, startMs: r.start, endMs: r.end,
            title: Format.spanTitle(title, minutes: Format.minutes(r.end - r.start), start: r.start, end: r.end, tz),
            notes: "Joined shuttle Wi-Fi \"\(r.network)\" \(Format.clock(r.start, tz)), \(off)\(whole)\n\n\(tagPrefix)\(tag)]")
    }

    static func how(_ source: String, _ detail: String) -> String {
        switch source {
        case "location": return "location"
        case "wifi": return "Wi-Fi \"\(detail)\""
        case "car": return "car Bluetooth connecting (\(detail))"
        case "shuttle": return "shuttle Wi-Fi \"\(detail)\""
        case "next-arrival": return "arriving at \(detail.lowercased())"
        default: return source
        }
    }
}
