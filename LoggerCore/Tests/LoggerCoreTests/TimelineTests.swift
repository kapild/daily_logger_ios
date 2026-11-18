import XCTest
@testable import LoggerCore

/// The Android app's shuttle and commute cases, run against the Swift port.
final class TimelineTests: XCTestCase {
    let geofenced: Set<Place> = [.home, .office]

    func eveningWithRestaurant(_ s: Signals) -> [Signal] {
        [
            s.make(at(9), .arrive, .office),
            s.make(at(16, 55), .leave, .office),
            s.on(at(16, 58)),
            s.off(at(17, 36)),
            s.make(at(18, 51), .arrive, .home),
        ]
    }

    func titles(_ signals: [Signal]) -> [String] {
        PlacesBuilder.build(PlaceTimeline.build(signals, geofenced: geofenced), now: at(23), tz: la).map(\.title)
    }

    func testRideRunsFromShuttleWifiOnToOff() {
        let t = PlaceTimeline.build(eveningWithRestaurant(Signals()), geofenced: geofenced)
        XCTAssertEqual(t.rides.map { [$0.start, $0.end] }, [[at(16, 58), at(17, 36)]])
        XCTAssertEqual(t.trips.map { [$0.start, $0.end] }, [[at(16, 55), at(18, 51)]])
    }

    func testBriefDropIsTheSameRide() {
        let s = Signals()
        let t = PlaceTimeline.build([s.on(at(8, 20)), s.off(at(8, 35)), s.on(at(8, 38)), s.off(at(9, 2))], geofenced: geofenced)
        XCTAssertEqual(t.rides.map { [$0.start, $0.end] }, [[at(8, 20), at(9, 2)]])
    }

    func testLongerBreakIsTwoRides() {
        let s = Signals()
        XCTAssertEqual(PlaceTimeline.build([s.on(at(8)), s.off(at(8, 20)), s.on(at(8, 45)), s.off(at(9, 5))], geofenced: geofenced).rides.count, 2)
    }

    func testEventsSplitTheRideFromTheDoorToDoorTrip() {
        let t = titles(eveningWithRestaurant(Signals()))
        XCTAssertTrue(t.contains { $0.hasPrefix("Commute home by shuttle | Dur: 38 mins |") }, "\(t)")
        XCTAssertTrue(t.contains { $0.hasPrefix("Work to home via shuttle | Dur: 1 hour 56 mins |") }, "\(t)")
        XCTAssertTrue(t.contains("Left office | At: 4:55 pm"), "\(t)")
        XCTAssertTrue(t.contains { $0.hasPrefix("At work | Dur: 7 hours 55 mins | Start: 9:00 am End: 4:55 pm") }, "\(t)")
    }

    func testCarConnectingEndsTheRide() {
        let s = Signals()
        let signals = [
            s.make(at(16, 55), .leave, .office),
            s.on(at(16, 58)),
            s.off(at(17, 38), source: "bluetooth"),
            s.make(at(17, 38), .carOn, source: "bluetooth", detail: "Tesla"),
            s.make(at(18, 30), .carOff, source: "bluetooth", detail: "Tesla"),
            s.make(at(18, 51), .arrive, .home),
        ]
        let t = titles(signals)
        XCTAssertTrue(t.contains { $0.hasPrefix("Commute home by shuttle | Dur: 40 mins |") }, "\(t)")
        XCTAssertTrue(t.contains { $0.hasPrefix("Work to home via shuttle and car | Dur: 1 hour 56 mins |") }, "\(t)")
        XCTAssertTrue(t.contains { $0.hasPrefix("Drive | Dur: 52 mins |") }, "\(t)")
    }

    func testCarCommute() {
        let s = Signals()
        let signals = [
            s.make(at(16, 55), .leave, .office),
            s.make(at(16, 56), .carOn, source: "bluetooth", detail: "Tesla"),
            s.make(at(17, 40), .carOff, source: "bluetooth", detail: "Tesla"),
            s.make(at(17, 42), .arrive, .home),
        ]
        let events = PlacesBuilder.build(PlaceTimeline.build(signals, geofenced: geofenced), now: at(23), tz: la)
        XCTAssertTrue(events.contains { $0.title.hasPrefix("Commute home by car | Dur: 47 mins |") })
        XCTAssertFalse(events.contains { $0.title.hasPrefix("Drive |") })
        let trip = events.first { $0.title.hasPrefix("Commute home") }!
        XCTAssertTrue(trip.notes.hasSuffix("[hc:pl:trip:i1]"), trip.notes)
    }

    func testBackWithinTenMinutesNeverLeft() {
        let s = Signals()
        let t = PlaceTimeline.build([
            s.make(at(9), .arrive, .office),
            s.make(at(12), .leave, .office),
            s.make(at(12, 5), .arrive, .office),
            s.make(at(17), .leave, .office),
        ], geofenced: geofenced)
        XCTAssertEqual(t.visits.count, 1)
        XCTAssertEqual(t.visits[0].end, at(17))
    }

    func testAFreshExitWaits() {
        let s = Signals()
        let signals = [s.make(at(9), .arrive, .office), s.make(at(17), .leave, .office)]
        let early = PlacesBuilder.build(PlaceTimeline.build(signals, geofenced: geofenced), now: at(17, 5), tz: la)
        XCTAssertFalse(early.contains { $0.title.hasPrefix("Left office") })
        let later = PlacesBuilder.build(PlaceTimeline.build(signals, geofenced: geofenced), now: at(17, 20), tz: la)
        XCTAssertTrue(later.contains { $0.title.hasPrefix("Left office") })
    }
}
