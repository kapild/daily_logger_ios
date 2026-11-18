import XCTest
@testable import LoggerCore

final class RulesTests: XCTestCase {
    /// Oct 19: geofences re-reported every place at 11:36 while at the office since 9.
    func testDropsRepeatedGeofenceBursts() {
        let s = Signals()
        let prior = s.make(0, .leave, .gym)
        let day = [
            s.make(at(8, 30), .leave, .home),
            s.make(at(8, 32), .carOn, source: "bluetooth"),
            s.make(at(9), .carOff, source: "bluetooth"),
            s.make(at(10, 19), .arrive, .office, source: "wifi"),
            s.make(at(11, 36), .leave, .home),
            s.make(at(11, 36), .leave, .gym),
            s.make(at(11, 36), .arrive, .office),
        ]
        XCTAssertEqual(Array(SignalRules.clean([prior] + day).dropFirst()), Array(day.prefix(4)))
    }

    func testShuttleOffNeedsAnOpenRide() {
        let s = Signals()
        XCTAssertFalse(SignalRules.shouldRecord(s.off(at(9)), history: []))
        let on = s.on(at(8))
        XCTAssertTrue(SignalRules.shouldRecord(s.off(at(9)), history: [on]))
        XCTAssertFalse(SignalRules.shouldRecord(s.on(at(8, 5)), history: [on]))
    }

    func testWifiRepeatIsSkippedButARealReturnIsKept() {
        let s = Signals()
        let a = s.make(at(9), .arrive, .office, source: "wifi")
        XCTAssertFalse(SignalRules.shouldRecord(s.make(at(9, 10), .arrive, .office, source: "wifi"), history: [a]))
        let left = s.make(at(12), .leave, .office)
        XCTAssertTrue(SignalRules.shouldRecord(s.make(at(13), .arrive, .office, source: "wifi"), history: [a, left]))
    }

    func testOpenRide() {
        let s = Signals()
        let on = s.on(at(17))
        XCTAssertEqual(SignalRules.openRide(history: [on], now: at(17, 30))?.id, on.id)
        XCTAssertNil(SignalRules.openRide(history: [on], now: at(22)))
        XCTAssertNil(SignalRules.openRide(history: [on, s.off(at(17, 40))], now: at(17, 45)))
    }
}
