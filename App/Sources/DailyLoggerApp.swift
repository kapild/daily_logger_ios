import BackgroundTasks
import SwiftUI
import UIKit

@main
struct DailyLoggerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Runs at every launch, including when iOS starts the app in the background
/// for a place, a Health update or a refresh.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshID = "dev.kapil.dailylogger.refresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = PlaceMonitor.shared // region events are delivered to this manager
        PlaceMonitor.shared.refreshRegions()
        HealthSource.shared.startObserving()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: nil) { task in
            Self.scheduleRefresh()
            let work = Task {
                await SyncCoordinator.shared.syncAll(reason: "Background refresh")
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        Self.scheduleRefresh()
        return true
    }

    /// Asks iOS for a refresh in about an hour; iOS decides the exact time.
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
