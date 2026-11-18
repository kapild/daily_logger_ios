import UIKit

/// Asks iOS for a little extra time to finish writing the calendar after a wake-up.
enum BackgroundTask {
    static func begin(_ name: String) -> UIBackgroundTaskIdentifier {
        var id = UIBackgroundTaskIdentifier.invalid
        id = UIApplication.shared.beginBackgroundTask(withName: name) {
            UIApplication.shared.endBackgroundTask(id)
        }
        return id
    }

    static func end(_ id: UIBackgroundTaskIdentifier) {
        if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
    }
}
