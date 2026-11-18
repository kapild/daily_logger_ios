import AppIntents

// Actions for the Shortcuts app. Personal automations ("When I join Wi-Fi
// GBUS", "When my iPhone connects to Tesla") run these in the background,
// which is how iOS lets an app notice Wi-Fi and Bluetooth changes.

struct JoinedWiFiIntent: AppIntent {
    static var title: LocalizedStringResource = "Log: Joined Wi-Fi"
    static var description = IntentDescription("Tells Daily Logger your iPhone joined a Wi-Fi network (home, office, or the shuttle).")
    static var openAppWhenRun = false

    @Parameter(title: "Network name") var network: String

    func perform() async throws -> some IntentResult {
        await Recorder.wifiJoined(network)
        return .result()
    }
}

struct LeftWiFiIntent: AppIntent {
    static var title: LocalizedStringResource = "Log: Left Wi-Fi"
    static var description = IntentDescription("Tells Daily Logger your iPhone left a Wi-Fi network. Used for getting off the shuttle.")
    static var openAppWhenRun = false

    @Parameter(title: "Network name") var network: String

    func perform() async throws -> some IntentResult {
        await Recorder.wifiLeft(network)
        return .result()
    }
}

struct CarConnectedIntent: AppIntent {
    static var title: LocalizedStringResource = "Log: Car connected"
    static var description = IntentDescription("Tells Daily Logger your car's Bluetooth connected: a drive starts.")
    static var openAppWhenRun = false

    @Parameter(title: "Car", default: "Tesla") var car: String

    func perform() async throws -> some IntentResult {
        await Recorder.car(connected: true, name: car)
        return .result()
    }
}

struct CarDisconnectedIntent: AppIntent {
    static var title: LocalizedStringResource = "Log: Car disconnected"
    static var description = IntentDescription("Tells Daily Logger your car's Bluetooth disconnected: the drive ends.")
    static var openAppWhenRun = false

    @Parameter(title: "Car", default: "Tesla") var car: String

    func perform() async throws -> some IntentResult {
        await Recorder.car(connected: false, name: car)
        return .result()
    }
}

struct SyncNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Daily Logger"
    static var description = IntentDescription("Rewrites the last few days of sleep, workouts, places and commutes to your calendar.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SyncCoordinator.shared.syncAll(reason: "Shortcut")
        return .result(dialog: "\(result)")
    }
}

struct LoggerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncNowIntent(),
            phrases: ["Sync \(.applicationName)"],
            shortTitle: "Sync now",
            systemImageName: "arrow.triangle.2.circlepath")
    }
}
