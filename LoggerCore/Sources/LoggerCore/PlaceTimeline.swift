import Foundation

/// One continuous stay at a place.
public final class Visit {
    public let place: Place
    public let start: Int64
    public let startId: Int64
    public let startSource: String
    public let startDetail: String
    /// False when only the exit was seen, never the arrival.
    public let startKnown: Bool
    /// Nil while you're still there.
    public var end: Int64?
    public var endId: Int64 = 0
    public var endSource = ""
    public var endDetail = ""
    /// False when no exit was seen; it only ended before the next arrival.
    public var endKnown = true

    init(place: Place, start: Int64, startId: Int64, startSource: String, startDetail: String, startKnown: Bool = true) {
        self.place = place
        self.start = start
        self.startId = startId
        self.startSource = startSource
        self.startDetail = startDetail
        self.startKnown = startKnown
    }
}

public struct Trip: Equatable {
    public let from: Place, to: Place, start: Int64, end: Int64, id: Int64
}

public struct Drive: Equatable {
    public let start: Int64, end: Int64, id: Int64, device: String
}

/// Time on the shuttle, from joining its Wi-Fi to the first sign you got off.
public struct ShuttleRide: Equatable, Hashable {
    public var start: Int64, end: Int64, id: Int64, network: String
    public var endSource = "wifi"
}

public struct Timeline {
    public let visits: [Visit]
    public let trips: [Trip]
    public let drives: [Drive]
    public let shuttleTimes: [Int64]
    public let rides: [ShuttleRide]
}

/// Turns the signal log into an ordered day: stay, exit, trip, arrival, stay, ...
/// A line-for-line port of the Android app's `PlaceTimeline`, so both phones
/// read a day the same way:
///  - A second "left" for the place you already left is ignored.
///  - For a geofenced place, seeing its Wi-Fi again after the geofence said you
///    left is not a return; only the geofence can bring you back.
///  - Back within 10 minutes means you never left.
///  - With no exit seen, the stay ends when the car or shuttle was detected.
///  - Shuttle rides run from joining its Wi-Fi to getting off; a drop of up
///    to 10 minutes is the same ride.
public enum PlaceTimeline {
    static let minute: Int64 = 60_000
    public static let flapMs = 10 * minute
    public static let commuteMaxMs = 180 * minute
    static let minDriveMs = 2 * minute
    static let maxDriveMs = 300 * minute
    public static let minStayMs = 10 * minute
    static let rideGapMs = 10 * minute
    static let minRideMs = 2 * minute
    static let maxRideMs = 180 * minute

    public static func build(_ signals: [Signal], geofenced: Set<Place>) -> Timeline {
        var visits: [Visit] = []
        var drives: [Drive] = []
        var shuttleTimes: [Int64] = []
        var rides: [ShuttleRide] = []
        var rideOpen: ShuttleRide?

        var current: Visit?
        var last: Visit?
        var hint: Signal?
        var carOn: Signal?

        func close(_ v: Visit, _ ts: Int64, _ id: Int64, _ source: String, _ detail: String, known: Bool) {
            v.end = ts
            v.endId = id
            v.endSource = source
            v.endDetail = detail
            v.endKnown = known
            current = nil
            last = v
            hint = nil
        }

        func moving(_ s: Signal, _ source: String) {
            guard let cur = current else { return }
            if geofenced.contains(cur.place) {
                if hint == nil { hint = s }
            } else {
                close(cur, s.ts, s.id, source, s.detail, known: true)
            }
        }

        for s in signals {
            switch s.type {
            case .arrive:
                guard let key = s.place, let place = Place(rawValue: key) else { continue }
                if let cur = current, cur.place == place {
                    hint = nil
                    continue
                }
                if current == nil, let prev = last, prev.place == place {
                    if s.source == "wifi" && geofenced.contains(place) { continue }
                    let leftAt = prev.end ?? s.ts
                    if s.ts - leftAt <= flapMs {
                        if prev.startKnown {
                            prev.end = nil
                            prev.endKnown = true
                            current = prev
                            last = nil
                            hint = nil
                            continue
                        }
                        visits.removeAll { $0 === prev }
                    }
                }
                if let cur = current {
                    if let h = hint, (minute...commuteMaxMs).contains(s.ts - h.ts) {
                        close(cur, h.ts, h.id, h.type == .shuttle ? "shuttle" : "car", h.detail, known: true)
                    } else {
                        close(cur, s.ts, s.id, "next-arrival", place.label, known: false)
                    }
                }
                let v = Visit(place: place, start: s.ts, startId: s.id, startSource: s.source, startDetail: s.detail)
                visits.append(v)
                current = v
                last = nil
                hint = nil

            case .leave:
                guard let key = s.place, let place = Place(rawValue: key) else { continue }
                if let cur = current {
                    if cur.place == place { close(cur, s.ts, s.id, s.source, s.detail, known: true) }
                } else if last == nil || last!.place != place {
                    let v = Visit(place: place, start: s.ts, startId: s.id, startSource: s.source, startDetail: s.detail, startKnown: false)
                    visits.append(v)
                    close(v, s.ts, s.id, s.source, s.detail, known: true)
                }

            case .carOn:
                if carOn == nil { carOn = s }
                moving(s, "car")

            case .carOff:
                if let on = carOn, (minDriveMs...maxDriveMs).contains(s.ts - on.ts) {
                    drives.append(Drive(start: on.ts, end: s.ts, id: on.id, device: on.detail))
                }
                carOn = nil

            case .shuttle:
                shuttleTimes.append(s.ts)
                if rideOpen == nil {
                    if let prev = rides.last, s.ts - prev.end <= rideGapMs {
                        rides.removeLast()
                        rideOpen = prev
                    } else {
                        rideOpen = ShuttleRide(start: s.ts, end: s.ts, id: s.id, network: s.detail)
                    }
                }
                moving(s, "shuttle")

            case .shuttleOff:
                if var open = rideOpen {
                    if (minRideMs...maxRideMs).contains(s.ts - open.start) {
                        open.end = s.ts
                        open.endSource = s.source
                        rides.append(open)
                    }
                    rideOpen = nil
                }
            }
        }

        // A short hop back to the place you just left isn't a new visit.
        var kept: [Visit] = []
        for v in visits {
            let briefReturn: Bool = {
                guard let prev = kept.last, prev.place == v.place, v.startKnown, let end = v.end else { return false }
                return end - v.start < minStayMs
            }()
            if !briefReturn { kept.append(v) }
        }

        // Every exit is followed by a trip to wherever you arrive next.
        var trips: [Trip] = []
        if kept.count > 1 {
            for i in 0..<(kept.count - 1) {
                let a = kept[i], b = kept[i + 1]
                guard let leftAt = a.end, a.endKnown, b.startKnown, a.place != b.place else { continue }
                if (minute...commuteMaxMs).contains(b.start - leftAt) {
                    trips.append(Trip(from: a.place, to: b.place, start: leftAt, end: b.start, id: a.endId))
                }
            }
        }
        return Timeline(visits: kept, trips: trips, drives: drives, shuttleTimes: shuttleTimes, rides: rides)
    }
}
