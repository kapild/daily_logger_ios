import Foundation

/// Titles and times, worded exactly as the Android app writes them.
public enum Format {
    private static func formatter(_ pattern: String, _ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = pattern
        return f
    }

    private static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }

    /// "8:02 am", as used in titles.
    public static func titleTime(_ ms: Int64, _ tz: TimeZone) -> String {
        formatter("h:mm a", tz).string(from: date(ms)).lowercased()
    }

    /// "8:02 AM", as used in notes.
    public static func clock(_ ms: Int64, _ tz: TimeZone) -> String {
        formatter("h:mm a", tz).string(from: date(ms))
    }

    /// "7 hours 20 mins", "45 mins", "1 hour", "1 hour 1 min".
    public static func longDur(minutes: Int64) -> String {
        let total = max(0, minutes)
        let h = total / 60
        let m = total % 60
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        let mins = m == 1 ? "1 min" : "\(m) mins"
        if h == 0 { return mins }
        if m == 0 { return hours }
        return "\(hours) \(mins)"
    }

    /// "1h 05m", "38m".
    public static func dur(minutes: Int64) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m < 10 ? "0" : "")\(m)m" : "\(m)m"
    }

    /// "Sleep | Dur: 7 hours 20 mins | Start: 11:02 pm End: 6:22 am"
    public static func spanTitle(_ name: String, minutes: Int64, start: Int64, end: Int64, _ tz: TimeZone) -> String {
        "\(name) | Dur: \(longDur(minutes: minutes)) | Start: \(titleTime(start, tz)) End: \(titleTime(end, tz))"
    }

    /// "Arrived home | At: 11:21 pm"
    public static func markerTitle(_ name: String, at: Int64, _ tz: TimeZone) -> String {
        "\(name) | At: \(titleTime(at, tz))"
    }

    public static func minutes(_ ms: Int64) -> Int64 { ms / 60_000 }

    /// The tag inside "[hc:<tag>]", or nil.
    public static func tag(in notes: String) -> String? {
        guard let open = notes.range(of: tagPrefix),
              let close = notes[open.upperBound...].firstIndex(of: "]") else { return nil }
        return String(notes[open.upperBound..<close])
    }
}
