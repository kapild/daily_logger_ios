import CoreLocation
import LoggerCore

/// Watches your saved places with iOS region monitoring. iOS wakes the app
/// (even if it was closed) when you enter or leave one, so this must be set
/// up at launch: see `AppDelegate`.
final class PlaceMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = PlaceMonitor()
    private let manager = CLLocationManager()
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private var pendingFix: ((CLLocation?) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    var hasAlways: Bool { authorization == .authorizedAlways }

    /// Asks for "While Using" first; iOS then offers "Always", which region monitoring needs.
    func requestAccess() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: manager.requestAlwaysAuthorization()
        }
    }

    /// Re-arms a region for every saved place and drops the rest. Safe to call any time.
    func refreshRegions() {
        let wanted = Settings.shared.logPlaces ? Settings.shared.locations : [:]
        for region in manager.monitoredRegions where wanted[region.identifier] == nil {
            manager.stopMonitoring(for: region)
        }
        for (key, loc) in wanted {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                radius: min(loc.radius, manager.maximumRegionMonitoringDistance),
                identifier: key)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    /// One location fix, for "Use my current location".
    func currentLocation(_ done: @escaping (CLLocation?) -> Void) {
        pendingFix = done
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestLocation()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        refreshRegions()
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handle(region, entered: true)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        handle(region, entered: false)
    }

    private func handle(_ region: CLRegion, entered: Bool) {
        guard let place = Place(rawValue: region.identifier) else { return }
        // Keep running briefly in the background to write the calendar.
        let task = BackgroundTask.begin("region")
        Task {
            await Recorder.geofence(place, entered: entered)
            BackgroundTask.end(task)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        pendingFix?(locations.last)
        pendingFix = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pendingFix?(nil)
        pendingFix = nil
    }
}
