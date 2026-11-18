import Foundation
import LoggerCore

/// The one place signals come in: geofences, Shortcuts automations (Wi-Fi and
/// car Bluetooth) and motion. Mirrors the Android app's receivers.
enum Recorder {
    private static var settings: Settings { Settings.shared }
    private static var store: SignalStore { SignalStore.shared }

    static func geofence(_ place: Place, entered: Bool, at date: Date = Date()) async {
        guard settings.logPlaces else { return }
        store.record(entered ? .arrive : .leave, place: place, source: "location", detail: "geofence", at: date)
        await SyncCoordinator.shared.syncPlaces(reason: "\(entered ? "Arrived" : "Left") \(place.label.lowercased())")
    }

    static func wifiJoined(_ name: String) async {
        guard settings.logPlaces else { return }
        // A shuttle network is never a place, even if the same name is listed under one.
        if settings.isShuttle(name) {
            store.record(.shuttle, source: "wifi", detail: name)
        } else {
            // Joining any other network while on a ride means you're off the shuttle.
            if let ride = store.openRide() { store.record(.shuttleOff, source: "wifi", detail: ride.detail) }
            if let place = settings.place(forWifi: name) {
                store.record(.arrive, place: place, source: "wifi", detail: name)
            }
        }
        await SyncCoordinator.shared.syncPlaces(reason: "Joined Wi-Fi \(name)")
    }

    static func wifiLeft(_ name: String) async {
        guard settings.logPlaces else { return }
        if settings.isShuttle(name), let ride = store.openRide() {
            store.record(.shuttleOff, source: "wifi", detail: ride.detail)
            await SyncCoordinator.shared.syncPlaces(reason: "Left Wi-Fi \(name)")
        }
    }

    static func car(connected: Bool, name: String) async {
        guard settings.logPlaces else { return }
        let car = name.isEmpty ? "Car" : name
        if connected {
            // Getting into the car ends a shuttle ride; logged first so the ride ends at the earliest sign.
            if let ride = store.openRide() { store.record(.shuttleOff, source: "bluetooth", detail: ride.detail) }
            store.record(.carOn, source: "bluetooth", detail: car)
        } else {
            store.record(.carOff, source: "bluetooth", detail: car)
        }
        await SyncCoordinator.shared.syncPlaces(reason: "Car \(connected ? "connected" : "disconnected")")
    }
}
