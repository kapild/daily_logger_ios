import SwiftUI

/// Step-by-step setup of the Shortcuts automations that feed Wi-Fi and car signals.
struct ShortcutsGuide: View {
    @ObservedObject private var settings = Settings.shared

    private var automations: [(String, String, String)] {
        let shuttle = settings.shuttleWifi.first ?? "GBUS"
        let home = settings.wifi["home"]?.first ?? "your home Wi-Fi"
        let office = settings.wifi["office"]?.first ?? "your office Wi-Fi"
        return [
            ("Shuttle on", "Wi-Fi › \(shuttle) › Joins", "Log: Joined Wi-Fi, Network name: \(shuttle)"),
            ("Shuttle off", "Wi-Fi › \(shuttle) › Leaves", "Log: Left Wi-Fi, Network name: \(shuttle)"),
            ("Car on", "Bluetooth › your car › Is Connected", "Log: Car connected"),
            ("Car off", "Bluetooth › your car › Is Disconnected", "Log: Car disconnected"),
            ("Home or office Wi-Fi", "Wi-Fi › \(home), \(office) › Joins", "Log: Joined Wi-Fi, with that network's name typed in (one automation per network)"),
        ]
    }

    var body: some View {
        List {
            Section {
                Text("In the Shortcuts app: Automation › + › pick the trigger below › choose **Run Immediately** and turn off **Notify When Run** › New Blank Automation › add the Daily Logger action.")
                    .font(.callout)
            }
            ForEach(automations, id: \.0) { name, trigger, action in
                Section(name) {
                    LabeledContent("When", value: trigger)
                    LabeledContent("Do", value: action)
                }
            }
            Section {
                Text("If your iOS version has no Bluetooth trigger, skip the car ones: drives are then worked out from the phone's motion sensor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Automations")
    }
}
