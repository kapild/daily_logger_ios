import Foundation

/// One sleep sample as Apple Health stores it (HealthKit's sleep analysis).
public struct SleepSample: Equatable, Sendable {
    public enum Stage: String, Sendable { case inBed, asleep, core, deep, rem, awake }
    public var uuid: String
    public var start: Int64
    public var end: Int64
    public var stage: Stage
    /// The app or device that recorded it ("Withings", "Kapil's Apple Watch").
    public var source: String

    public init(uuid: String, start: Int64, end: Int64, stage: Stage, source: String) {
        self.uuid = uuid
        self.start = start
        self.end = end
        self.stage = stage
        self.source = source
    }
}

/// One night (or nap): the samples from one source that run together.
public struct SleepSession: Equatable, Sendable {
    public var samples: [SleepSample]
    public var source: String { samples[0].source }
    public var start: Int64 { samples.map(\.start).min()! }
    public var end: Int64 { samples.map(\.end).max()! }

    public func total(_ stages: SleepSample.Stage...) -> Int64 {
        samples.filter { stages.contains($0.stage) }.reduce(0) { $0 + $1.end - $1.start }
    }

    /// Time asleep across all stages, or the whole time in bed if no stages were recorded.
    public var asleepMs: Int64 {
        let asleep = total(.asleep, .core, .deep, .rem)
        return asleep > 0 ? asleep : end - start
    }
}

public enum SleepBuilder {
    /// Samples further apart than this belong to different sessions.
    static let gapMs: Int64 = 60 * 60_000

    /// Groups samples into sessions, per source, oldest first.
    public static func sessions(_ samples: [SleepSample]) -> [SleepSession] {
        var out: [SleepSession] = []
        for (_, list) in Dictionary(grouping: samples, by: \.source) {
            var current: [SleepSample] = []
            var currentEnd: Int64 = .min
            for s in list.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
                if !current.isEmpty && s.start - currentEnd > gapMs {
                    out.append(SleepSession(samples: current))
                    current = []
                }
                current.append(s)
                currentEnd = max(currentEnd, s.end)
            }
            if !current.isEmpty { out.append(SleepSession(samples: current)) }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// "Sleep | Dur: 6 hours 47 mins | Start: 11:24 pm End: 6:29 am", with the
    /// stages in the notes, as the Android app writes it.
    public static func event(_ s: SleepSession, tz: TimeZone) -> DesiredEvent {
        let clock = { (ms: Int64) in Format.clock(ms, tz) }
        let d = { (ms: Int64) in Format.dur(minutes: Format.minutes(ms)) }
        let staged = s.samples.contains { $0.stage != .inBed }
        let deepSegments = s.samples.filter { $0.stage == .deep }.sorted { $0.start < $1.start }
        let tag = "sleep:hk:\(s.samples.min { $0.start < $1.start }!.uuid)"
        var lines = ["Bedtime \(clock(s.start)), woke \(clock(s.end))", "Time in bed: \(d(s.end - s.start))"]
        if !staged {
            lines.append("No sleep stages recorded.")
        } else {
            lines.append("Asleep: \(d(s.asleepMs))")
            lines.append("")
            let n = deepSegments.count
            lines.append("Deep: \(d(s.total(.deep))) in \(n) \(n == 1 ? "segment" : "segments")")
            for seg in deepSegments {
                lines.append("  • \(clock(seg.start)) – \(clock(seg.end)) (\(d(seg.end - seg.start)))")
            }
            lines.append("REM: \(d(s.total(.rem)))")
            lines.append("Light: \(d(s.total(.core)))")
            let unstaged = s.total(.asleep)
            if unstaged > 0 { lines.append("Asleep, no stage: \(d(unstaged))") }
            lines.append("Awake: \(d(s.total(.awake)))")
        }
        lines.append("")
        lines.append("Source: \(s.source)")
        lines.append("\(tagPrefix)\(tag)]")
        return DesiredEvent(
            tag: tag, startMs: s.start, endMs: s.end,
            title: Format.spanTitle("Sleep", minutes: Format.minutes(s.asleepMs), start: s.start, end: s.end, tz),
            notes: lines.joined(separator: "\n"))
    }
}

/// A workout as the app needs it.
public struct WorkoutInfo: Equatable, Sendable {
    public var uuid: String
    public var name: String
    public var start: Int64
    public var end: Int64
    public var source: String

    public init(uuid: String, name: String, start: Int64, end: Int64, source: String) {
        self.uuid = uuid
        self.name = name
        self.start = start
        self.end = end
        self.source = source
    }
}

public enum WorkoutBuilder {
    /// "Run | Dur: 32 mins | Start: 6:10 am End: 6:42 am"
    public static func event(_ w: WorkoutInfo, tz: TimeZone) -> DesiredEvent {
        let tag = "ex:hk:\(w.uuid)"
        let minutes = Format.minutes(w.end - w.start)
        let notes = [
            "\(w.name), \(Format.clock(w.start, tz)) – \(Format.clock(w.end, tz))",
            "Duration: \(Format.dur(minutes: minutes))",
            "",
            "Source: \(w.source)",
            "\(tagPrefix)\(tag)]",
        ].joined(separator: "\n")
        return DesiredEvent(
            tag: tag, startMs: w.start, endMs: w.end,
            title: Format.spanTitle(w.name, minutes: minutes, start: w.start, end: w.end, tz),
            notes: notes)
    }
}

/// One reading from the phone's motion sensor (CoreMotion activity).
public struct MotionSample: Equatable, Sendable {
    public var start: Int64
    public var automotive: Bool
    /// Low-confidence readings are ignored.
    public var confident: Bool

    public init(start: Int64, automotive: Bool, confident: Bool) {
        self.start = start
        self.automotive = automotive
        self.confident = confident
    }
}

/// Drives from motion readings, for when no car Bluetooth automation is set up.
public enum DriveSegments {
    static let mergeGapMs: Int64 = 4 * 60_000
    static let minMs: Int64 = 3 * 60_000

    /// Runs of confident "automotive" readings; each ends when the next
    /// confident non-automotive reading starts. Stops of up to 4 minutes (lights,
    /// traffic) are part of the same drive.
    public static func from(_ samples: [MotionSample], now: Int64) -> [(start: Int64, end: Int64)] {
        var raw: [(Int64, Int64)] = []
        var open: Int64?
        for s in samples.sorted(by: { $0.start < $1.start }) where s.confident {
            if s.automotive {
                if open == nil { open = s.start }
            } else if let o = open {
                raw.append((o, s.start))
                open = nil
            }
        }
        _ = now // a drive still in progress isn't written until it ends
        var merged: [(start: Int64, end: Int64)] = []
        for (s, e) in raw {
            if let last = merged.last, s - last.end <= mergeGapMs {
                merged[merged.count - 1].end = e
            } else {
                merged.append((s, e))
            }
        }
        return merged.filter { $0.end - $0.start >= minMs }
    }
}
