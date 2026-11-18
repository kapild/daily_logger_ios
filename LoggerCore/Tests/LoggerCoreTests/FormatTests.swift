import XCTest
@testable import LoggerCore

final class FormatTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(Format.longDur(minutes: 440), "7 hours 20 mins")
        XCTAssertEqual(Format.longDur(minutes: 45), "45 mins")
        XCTAssertEqual(Format.longDur(minutes: 60), "1 hour")
        XCTAssertEqual(Format.longDur(minutes: 61), "1 hour 1 min")
        XCTAssertEqual(Format.dur(minutes: 65), "1h 05m")
        XCTAssertEqual(Format.dur(minutes: 38), "38m")
    }

    func testTitles() {
        XCTAssertEqual(Format.markerTitle("Arrived home", at: at(23, 21), la), "Arrived home | At: 11:21 pm")
        XCTAssertEqual(
            Format.spanTitle("Drive", minutes: 23, start: at(8, 1), end: at(8, 24), la),
            "Drive | Dur: 23 mins | Start: 8:01 am End: 8:24 am")
    }

    func testTagParsing() {
        XCTAssertEqual(Format.tag(in: "Left home at 8:01 AM\n\n[hc:pl:leave:i12]"), "pl:leave:i12")
        XCTAssertNil(Format.tag(in: "no tag"))
    }
}

final class ReconcileTests: XCTestCase {
    let a = DesiredEvent(tag: "pl:trip:i1", startMs: 1_000, endMs: 61_000, title: "A", notes: "x\n[hc:pl:trip:i1]")
    let b = DesiredEvent(tag: "pl:trip:i2", startMs: 2_000, endMs: 62_000, title: "B", notes: "y\n[hc:pl:trip:i2]")

    func testInsertUpdateDeleteAndDuplicates() {
        let existing = [
            ExistingEvent(id: "1", tag: a.tag, startMs: a.startMs, endMs: a.endMs, title: a.title, notes: a.notes + "\r\n"),
            ExistingEvent(id: "2", tag: a.tag, startMs: a.startMs, endMs: a.endMs, title: a.title, notes: a.notes),
            ExistingEvent(id: "3", tag: "pl:trip:i9", startMs: 5_000, endMs: 6_000, title: "old", notes: ""),
            ExistingEvent(id: "6", tag: "pl:trip:82", startMs: 5_000, endMs: 6_000, title: "from Android", notes: ""),
            ExistingEvent(id: "4", tag: "sleep:hk:x", startMs: 5_000, endMs: 6_000, title: "keep", notes: ""),
            ExistingEvent(id: "5", tag: b.tag, startMs: b.startMs, endMs: b.endMs, title: "B old", notes: b.notes),
        ]
        let plan = Reconcile.plan(desired: [a, b], existing: existing, isStale: PlacesBuilder.isOwnTag, staleFromMs: 0)
        XCTAssertEqual(plan.inserts, [])
        XCTAssertEqual(plan.unchanged, 1)
        XCTAssertEqual(plan.updates.map(\.id), ["5"])
        XCTAssertEqual(Set(plan.deletes), ["2", "3"])
    }

    func testAndroidsCopyOfANightIsNotDoubled() {
        let night = DesiredEvent(tag: "sleep:hk:u1", startMs: 0, endMs: 8 * 3_600_000, title: "Sleep", notes: "")
        let nap = DesiredEvent(tag: "sleep:hk:u2", startMs: 14 * 3_600_000, endMs: 15 * 3_600_000, title: "Sleep", notes: "")
        let android = ExistingEvent(id: "9", tag: "sleep:abc", startMs: 600_000, endMs: 8 * 3_600_000, title: "Sleep", notes: "")
        XCTAssertEqual(Reconcile.withoutOtherAppsCopies([night, nap], existing: [android]), [nap])
    }

    func testMissingIsInserted() {
        XCTAssertEqual(Reconcile.plan(desired: [a], existing: []).inserts, [a])
    }
}

final class HealthTests: XCTestCase {
    func testSleepSessionAndTitle() {
        let src = "Withings"
        let samples = [
            SleepSample(uuid: "u1", start: at(23, 24, day: 12), end: at(6, 29), stage: .inBed, source: src),
            SleepSample(uuid: "u2", start: at(23, 40, day: 12), end: at(0, 22), stage: .deep, source: src),
            SleepSample(uuid: "u3", start: at(0, 22), end: at(3, 0), stage: .core, source: src),
            SleepSample(uuid: "u4", start: at(3, 0), end: at(3, 18), stage: .awake, source: src),
            SleepSample(uuid: "u5", start: at(3, 18), end: at(6, 29), stage: .rem, source: src),
            SleepSample(uuid: "nap", start: at(14), end: at(14, 30), stage: .asleep, source: src),
        ]
        let sessions = SleepBuilder.sessions(samples)
        XCTAssertEqual(sessions.count, 2)
        let e = SleepBuilder.event(sessions[0], tz: la)
        XCTAssertEqual(e.title, "Sleep | Dur: 6 hours 31 mins | Start: 11:24 pm End: 6:29 am")
        XCTAssertEqual(e.tag, "sleep:hk:u1")
        XCTAssertTrue(e.notes.contains("Deep: 42m in 1 segment"), e.notes)
        XCTAssertTrue(e.notes.contains("Awake: 18m"), e.notes)
        XCTAssertTrue(e.notes.hasSuffix("Source: Withings\n[hc:sleep:hk:u1]"), e.notes)
    }

    func testWorkout() {
        let e = WorkoutBuilder.event(WorkoutInfo(uuid: "w", name: "Run", start: at(6, 10), end: at(6, 42), source: "Watch"), tz: la)
        XCTAssertEqual(e.title, "Run | Dur: 32 mins | Start: 6:10 am End: 6:42 am")
        XCTAssertEqual(e.tag, "ex:hk:w")
    }

    func testDrivesFromMotion() {
        let m = [
            MotionSample(start: at(8), automotive: false, confident: true),
            MotionSample(start: at(8, 2), automotive: true, confident: true),
            MotionSample(start: at(8, 10), automotive: false, confident: true), // a red light
            MotionSample(start: at(8, 12), automotive: true, confident: true),
            MotionSample(start: at(8, 15), automotive: true, confident: false),
            MotionSample(start: at(8, 30), automotive: false, confident: true),
            MotionSample(start: at(9), automotive: true, confident: true),
            MotionSample(start: at(9, 1), automotive: false, confident: true), // too short
        ]
        let d = DriveSegments.from(m, now: at(10))
        XCTAssertEqual(d.map { [$0.start, $0.end] }, [[at(8, 2), at(8, 30)]])
    }
}
