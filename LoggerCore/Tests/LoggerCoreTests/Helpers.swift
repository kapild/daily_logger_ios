import Foundation
@testable import LoggerCore

let la = TimeZone(identifier: "America/Los_Angeles")!

/// Epoch ms for 2026-10-13 at hour:minute in Los Angeles (or another day).
func at(_ hour: Int, _ minute: Int = 0, day: Int = 13) -> Int64 {
    var c = DateComponents()
    c.year = 2026; c.month = 10; c.day = day; c.hour = hour; c.minute = minute
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = la
    return Int64(cal.date(from: c)!.timeIntervalSince1970 * 1000)
}

final class Signals {
    private var next: Int64 = 1
    func make(_ ts: Int64, _ type: SignalType, _ place: Place? = nil, source: String = "location", detail: String = "") -> Signal {
        defer { next += 1 }
        return Signal(id: next, ts: ts, type: type, place: place?.rawValue, source: source, detail: detail)
    }
    func on(_ ts: Int64) -> Signal { make(ts, .shuttle, source: "wifi", detail: "GBUS") }
    func off(_ ts: Int64, source: String = "wifi") -> Signal { make(ts, .shuttleOff, source: source, detail: "GBUS") }
}
