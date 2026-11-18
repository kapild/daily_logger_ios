import LoggerCore
import SwiftUI

/// The raw signals the app has seen, newest first, like the Android Found tab.
struct SignalsView: View {
    @State private var signals: [Signal] = []

    var body: some View {
        List {
            if signals.isEmpty {
                Text("Nothing yet. Signals appear as you arrive, leave, drive and ride.").foregroundStyle(.secondary)
            }
            ForEach(signals) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(s)).font(.headline)
                    Text(Date(timeIntervalSince1970: TimeInterval(s.ts) / 1000).formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Detected by \(how(s))").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .onDelete { idx in
                for i in idx { SignalStore.shared.delete(signals[i].id) }
                reload()
            }
        }
        .navigationTitle("Found")
        .refreshable { reload() }
        .onAppear { reload() }
    }

    private func reload() {
        signals = Array(SignalStore.shared.between(Date().addingTimeInterval(-14 * 86_400), Date()).reversed())
    }

    private func title(_ s: Signal) -> String {
        let place = s.place.flatMap(Place.init(rawValue:))?.label.lowercased() ?? ""
        switch s.type {
        case .arrive: return "Arrived \(place)"
        case .leave: return "Left \(place)"
        case .carOn: return "Car connected"
        case .carOff: return "Car disconnected"
        case .shuttle: return "On shuttle Wi-Fi"
        case .shuttleOff: return "Off the shuttle"
        }
    }

    private func how(_ s: Signal) -> String {
        switch s.source {
        case "wifi": return "Wi-Fi \(s.detail)"
        case "bluetooth": return s.detail
        case "motion": return "motion"
        default: return "location"
        }
    }
}

/// What each sync did, newest first.
struct ActivityView: View {
    @State private var lines: [String] = []

    var body: some View {
        List(lines, id: \.self) { Text($0).font(.footnote) }
            .navigationTitle("Activity")
            .onAppear { lines = SyncLog.all() }
            .refreshable { lines = SyncLog.all() }
    }
}
