import Foundation

/// What a signal says happened. `shuttle` is joining the shuttle Wi-Fi and
/// `shuttleOff` is getting off it (leaving its Wi-Fi or the car connecting).
public enum SignalType: String, Codable, CaseIterable, Sendable {
    case arrive, leave, carOn, carOff, shuttle, shuttleOff

    public var isMovement: Bool { true }
}

/// One raw observation: "left home at 8:05" (location), "car connected at 8:07".
/// Times are epoch milliseconds, like the Android app.
public struct Signal: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64
    public var ts: Int64
    public var type: SignalType
    /// `Place.rawValue` for arrive and leave, otherwise nil.
    public var place: String?
    /// "location", "wifi", "bluetooth" or "motion".
    public var source: String
    /// Wi-Fi name, car name, ...
    public var detail: String

    public init(id: Int64, ts: Int64, type: SignalType, place: String?, source: String, detail: String) {
        self.id = id
        self.ts = ts
        self.type = type
        self.place = place
        self.source = source
        self.detail = detail
    }
}

/// The places Daily Logger knows. `markers` writes "Arrived ..." / "Left ..."
/// events; `spanTitle` writes one event covering the whole stay.
public enum Place: String, Codable, CaseIterable, Sendable {
    case home, office, gym

    public var label: String {
        switch self {
        case .home: return "Home"
        case .office: return "Office"
        case .gym: return "Gym"
        }
    }

    public var defaultRadius: Double {
        switch self {
        case .home: return 150
        case .office: return 250
        case .gym: return 120
        }
    }

    public var markers: Bool { self != .gym }

    public var spanTitle: String? {
        switch self {
        case .home: return nil
        case .office: return "At work"
        case .gym: return "Gym"
        }
    }
}

/// What a calendar event should look like. Every event's notes end with
/// "[hc:<tag>]" so a later run can find it again; the tags match the Android app.
public struct DesiredEvent: Equatable, Sendable {
    public var tag: String
    public var startMs: Int64
    public var endMs: Int64
    public var title: String
    public var notes: String
    public var allDay: Bool

    public init(tag: String, startMs: Int64, endMs: Int64, title: String, notes: String, allDay: Bool = false) {
        self.tag = tag
        self.startMs = startMs
        self.endMs = endMs
        self.title = title
        self.notes = notes
        self.allDay = allDay
    }
}

public let tagPrefix = "[hc:"
