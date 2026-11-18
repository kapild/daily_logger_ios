import Foundation

/// Which signals are worth keeping. Ported from the Android app's `Signals.record`
/// and `SignalFilter`.
public enum SignalRules {
    static let wifiDedupeMs: Int64 = 20 * 60_000
    /// A shuttle ride still counts as open for this long without an "off".
    public static let rideGiveUpMs: Int64 = 4 * 60 * 60_000

    /// A place signal that changes nothing: "left X" when the last thing known
    /// about X is that you left it, or "arrived X" with nothing since you last
    /// arrived at X (geofences sometimes re-report every place at once).
    public static func isNoOp(_ s: Signal, lastForPlace: Signal?, lastMovement: Signal?) -> Bool {
        switch s.type {
        case .leave: return lastForPlace?.type == .leave
        case .arrive: return lastMovement?.type == .arrive && lastMovement?.place == s.place
        default: return false
        }
    }

    /// `signals` (oldest first) without the no-op place signals.
    public static func clean(_ signals: [Signal]) -> [Signal] {
        var out: [Signal] = []
        var lastByPlace: [String: Signal] = [:]
        var lastMovement: Signal?
        for s in signals {
            if let place = s.place, isNoOp(s, lastForPlace: lastByPlace[place], lastMovement: lastMovement) { continue }
            out.append(s)
            if let place = s.place { lastByPlace[place] = s }
            lastMovement = s
        }
        return out
    }

    /// Whether to log `new`, given what is already logged (oldest first).
    public static func shouldRecord(_ new: Signal, history: [Signal]) -> Bool {
        if new.type == .shuttle || new.type == .shuttleOff {
            // On and off alternate; a repeat within 20 minutes adds nothing, and
            // "off" only means something while a ride is open.
            let last = history.last { $0.type == .shuttle || $0.type == .shuttleOff }
            let repeated = last?.type == new.type && new.ts - (last?.ts ?? .min) < wifiDedupeMs
            let offWithoutRide = new.type == .shuttleOff && last?.type != .shuttle
            if repeated || offWithoutRide { return false }
        } else if new.source == "wifi", let place = new.place {
            // Joining the same network again within 20 minutes, with nothing in between.
            let last = history.last { $0.place == place }
            if last?.type == new.type && new.ts - (last?.ts ?? .min) < wifiDedupeMs { return false }
        }
        if new.place != nil {
            let lastForPlace = history.last { $0.place == new.place }
            if isNoOp(new, lastForPlace: lastForPlace, lastMovement: history.last) { return false }
        }
        return true
    }

    /// The shuttle signal that opened the ride in progress, if any.
    public static func openRide(history: [Signal], now: Int64) -> Signal? {
        guard let last = history.last(where: { $0.type == .shuttle || $0.type == .shuttleOff }),
              last.type == .shuttle, now - last.ts < rideGiveUpMs else { return nil }
        return last
    }
}
