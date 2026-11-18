import Foundation
import LoggerCore

/// Where a place is: centre and radius in metres.
struct PlaceLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var radius: Double
}

/// Everything you set up in the app, kept in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var calendarID: String? { didSet { d.set(calendarID, forKey: "calendarID") } }
    @Published var logSleep: Bool { didSet { d.set(logSleep, forKey: "logSleep") } }
    @Published var logWorkouts: Bool { didSet { d.set(logWorkouts, forKey: "logWorkouts") } }
    @Published var logPlaces: Bool { didSet { d.set(logPlaces, forKey: "logPlaces") } }
    /// Use the phone's motion sensor for drives when no car Bluetooth automation has fired.
    @Published var drivesFromMotion: Bool { didSet { d.set(drivesFromMotion, forKey: "drivesFromMotion") } }
    @Published var locations: [String: PlaceLocation] { didSet { save(locations, "locations") } }
    /// Wi-Fi names that mean you're at a place, by place.
    @Published var wifi: [String: [String]] { didSet { save(wifi, "wifi") } }
    @Published var shuttleWifi: [String] { didSet { save(shuttleWifi, "shuttleWifi") } }

    private init() {
        calendarID = d.string(forKey: "calendarID")
        logSleep = d.object(forKey: "logSleep") as? Bool ?? true
        logWorkouts = d.object(forKey: "logWorkouts") as? Bool ?? true
        logPlaces = d.object(forKey: "logPlaces") as? Bool ?? true
        drivesFromMotion = d.object(forKey: "drivesFromMotion") as? Bool ?? true
        locations = Self.load("locations") ?? [:]
        wifi = Self.load("wifi") ?? [:]
        shuttleWifi = Self.load("shuttleWifi") ?? ["GBUS"]
    }

    func location(_ p: Place) -> PlaceLocation? { locations[p.rawValue] }

    func place(forWifi name: String) -> Place? {
        Place.allCases.first { (wifi[$0.rawValue] ?? []).contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
    }

    func isShuttle(_ name: String) -> Bool {
        shuttleWifi.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    var geofenced: Set<Place> { Set(Place.allCases.filter { location($0) != nil }) }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        d.set(try? JSONEncoder().encode(v), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Small status lines shown in Setup.
    var lastSync: String {
        get { d.string(forKey: "lastSync") ?? "Not synced yet." }
        set { d.set(newValue, forKey: "lastSync") }
    }

    var motionCheckedUntil: Date? {
        get { d.object(forKey: "motionCheckedUntil") as? Date }
        set { d.set(newValue, forKey: "motionCheckedUntil") }
    }
}
