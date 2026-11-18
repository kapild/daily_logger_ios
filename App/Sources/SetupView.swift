import CoreMotion
import EventKit
import LoggerCore
import SwiftUI

struct SetupView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var places = PlaceMonitor.shared
    @State private var calendars: [EKCalendar] = []
    @State private var calendarOK = CalendarStore.shared.authorized
    @State private var healthAsked = UserDefaults.standard.bool(forKey: "healthAsked")
    @State private var status = Settings.shared.lastSync
    @State private var syncing = false

    var body: some View {
        Form {
            Section {
                Text(status).font(.footnote).foregroundStyle(.secondary)
                Button(syncing ? "Syncing…" : "Sync now") {
                    syncing = true
                    Task {
                        status = await SyncCoordinator.shared.syncAll(reason: "Sync now")
                        syncing = false
                    }
                }
                .disabled(syncing)
            } header: { Text("Status") }

            Section {
                permission("Apple Health (sleep, workouts)", ok: healthAsked) {
                    Task {
                        try? await HealthSource.shared.requestAccess()
                        UserDefaults.standard.set(true, forKey: "healthAsked")
                        healthAsked = true
                    }
                }
                permission("Calendar (full access)", ok: calendarOK) {
                    Task {
                        calendarOK = (try? await CalendarStore.shared.requestAccess()) ?? false
                        calendars = CalendarStore.shared.writableCalendars()
                    }
                }
                permission("Location: Always (places)", ok: places.hasAlways) {
                    places.requestAccess()
                }
                permission("Motion (drives without the car automation)", ok: MotionDrives.authorized) {
                    // Any motion query brings up the permission prompt.
                    Task { await MotionDrives.check() }
                }
            } header: { Text("1. Permissions") } footer: {
                Text("Apple Health doesn't say whether you allowed reading, so this shows ✓ once you've been asked. If sleep doesn't appear, check Settings › Health › Data Access › Daily Logger.")
            }

            Section {
                Picker("Calendar", selection: $settings.calendarID) {
                    Text("Choose…").tag(String?.none)
                    ForEach(calendars, id: \.calendarIdentifier) { c in
                        Text("\(c.title) (\(c.source.title))").tag(Optional(c.calendarIdentifier))
                    }
                }
                Toggle("Sleep", isOn: $settings.logSleep)
                Toggle("Workouts", isOn: $settings.logWorkouts)
                Toggle("Places, drives and commutes", isOn: $settings.logPlaces)
                    .onChange(of: settings.logPlaces) { _, _ in places.refreshRegions() }
            } header: { Text("2. What to log, and where") } footer: {
                Text("Pick your Logger calendar so new events land next to the ones the Android app wrote. Google calendars appear here once your Google account is added under Settings › Apps › Calendar › Calendar Accounts.")
            }

            Section {
                ForEach(Place.allCases, id: \.self) { p in
                    NavigationLink { PlaceEditor(place: p) } label: {
                        LabeledContent(p.label, value: placeSummary(p))
                    }
                }
                LabeledContent("Shuttle Wi-Fi") {
                    TextField("GBUS", text: list($settings.shuttleWifi)).multilineTextAlignment(.trailing)
                }
                Toggle("Drives from motion", isOn: $settings.drivesFromMotion)
            } header: { Text("3. Places") } footer: {
                Text("Drives from motion are used only until the car Bluetooth automation runs once, and never during a shuttle ride.")
            }

            Section {
                NavigationLink("Set up the 5 automations") { ShortcutsGuide() }
            } header: { Text("4. Shortcuts automations") } footer: {
                Text("iOS only tells apps about Wi-Fi and Bluetooth through Shortcuts automations. They take a few minutes to set up, once.")
            }
        }
        .navigationTitle("Daily Logger")
        .onAppear {
            calendarOK = CalendarStore.shared.authorized
            if calendarOK { calendars = CalendarStore.shared.writableCalendars() }
            status = Settings.shared.lastSync
        }
    }

    private func placeSummary(_ p: Place) -> String {
        let loc = settings.location(p) != nil ? "location set" : "no location"
        let nets = settings.wifi[p.rawValue] ?? []
        return nets.isEmpty ? loc : "\(loc), \(nets.joined(separator: ", "))"
    }

    @ViewBuilder
    private func permission(_ name: String, ok: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text((ok ? "✓  " : "✗  ") + name)
            Spacer()
            if !ok { Button("Allow", action: action) }
        }
    }
}

/// Binds a comma-separated text field to a list of names.
func list(_ binding: Binding<[String]>) -> Binding<String> {
    Binding(
        get: { binding.wrappedValue.joined(separator: ", ") },
        set: { binding.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
}

struct PlaceEditor: View {
    let place: Place
    @ObservedObject private var settings = Settings.shared
    @State private var locating = false

    var body: some View {
        Form {
            Section {
                if let loc = settings.location(place) {
                    LabeledContent("Centre", value: String(format: "%.5f, %.5f", loc.latitude, loc.longitude))
                    Stepper("Radius: \(Int(loc.radius)) m", value: radius, in: 100...500, step: 25)
                    Button("Remove location", role: .destructive) {
                        settings.locations[place.rawValue] = nil
                        PlaceMonitor.shared.refreshRegions()
                    }
                }
                Button(locating ? "Finding you…" : "Use my current location") {
                    locating = true
                    PlaceMonitor.shared.currentLocation { loc in
                        locating = false
                        guard let loc else { return }
                        settings.locations[place.rawValue] = PlaceLocation(
                            latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                            radius: settings.location(place)?.radius ?? place.defaultRadius)
                        PlaceMonitor.shared.refreshRegions()
                    }
                }
                .disabled(locating)
            } header: { Text("Location") } footer: {
                Text("Stand at \(place.label.lowercased()) and tap the button. iOS tells the app when you arrive or leave.")
            }
            Section {
                TextField("Network names, comma separated", text: list(wifiBinding))
            } header: { Text("Wi-Fi") } footer: {
                Text("Joining one of these (through the Wi-Fi automation) also counts as arriving here.")
            }
        }
        .navigationTitle(place.label)
    }

    private var radius: Binding<Double> {
        Binding(
            get: { settings.location(place)?.radius ?? place.defaultRadius },
            set: { r in
                if var loc = settings.location(place) {
                    loc.radius = r
                    settings.locations[place.rawValue] = loc
                    PlaceMonitor.shared.refreshRegions()
                }
            })
    }

    private var wifiBinding: Binding<[String]> {
        Binding(get: { settings.wifi[place.rawValue] ?? [] }, set: { settings.wifi[place.rawValue] = $0 })
    }
}
