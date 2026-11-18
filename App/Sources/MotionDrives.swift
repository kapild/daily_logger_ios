import CoreMotion
import LoggerCore

/// Drives from the phone's motion sensor, for when the car Bluetooth
/// automation isn't set up. iOS keeps a week of motion history, so drives are
/// found even if the app wasn't running.
enum MotionDrives {
    private static let manager = CMMotionActivityManager()

    static var available: Bool { CMMotionActivityManager.isActivityAvailable() }

    static var authorized: Bool { CMMotionActivityManager.authorizationStatus() == .authorized }

    /// Reads motion since the last check and logs car on/off signals for drives
    /// that no other signal already covers. Skipped once a car Bluetooth
    /// automation has fired in the last two weeks, and during shuttle rides.
    static func check() async {
        guard Settings.shared.logPlaces, Settings.shared.drivesFromMotion, available,
              CMMotionActivityManager.authorizationStatus() != .denied else { return }
        let now = Date()
        let all = SignalStore.shared.all()
        let twoWeeks = Int64((now.timeIntervalSince1970 - 14 * 86_400) * 1000)
        if all.contains(where: { $0.type == .carOn && $0.source == "bluetooth" && $0.ts > twoWeeks }) { return }

        let from = max(Settings.shared.motionCheckedUntil ?? now.addingTimeInterval(-86_400), now.addingTimeInterval(-6 * 86_400))
        let samples: [MotionSample] = await withCheckedContinuation { cont in
            manager.queryActivityStarting(from: from.addingTimeInterval(-15 * 60), to: now, to: .main) { activities, _ in
                let list = (activities ?? []).map {
                    MotionSample(
                        start: Int64($0.startDate.timeIntervalSince1970 * 1000),
                        automotive: $0.automotive,
                        confident: $0.confidence != .low)
                }
                cont.resume(returning: list)
            }
        }
        let drives = DriveSegments.from(samples, now: Int64(now.timeIntervalSince1970 * 1000))
        var latestEnd = from
        for d in drives {
            // A drive that overlaps a shuttle ride is the shuttle bus.
            let shuttle = all.contains { ($0.type == .shuttle || $0.type == .shuttleOff) && $0.ts >= d.start - 10 * 60_000 && $0.ts <= d.end }
            let covered = all.contains { ($0.type == .carOn || $0.type == .carOff) && $0.ts >= d.start - 5 * 60_000 && $0.ts <= d.end + 5 * 60_000 }
            if shuttle || covered { continue }
            let start = Date(timeIntervalSince1970: TimeInterval(d.start) / 1000)
            let end = Date(timeIntervalSince1970: TimeInterval(d.end) / 1000)
            SignalStore.shared.record(.carOn, source: "motion", detail: "Driving", at: start)
            SignalStore.shared.record(.carOff, source: "motion", detail: "Driving", at: end)
            latestEnd = max(latestEnd, end)
        }
        // A drive still going isn't finished; look again from its start next time.
        Settings.shared.motionCheckedUntil = max(latestEnd, now.addingTimeInterval(-30 * 60))
    }
}
