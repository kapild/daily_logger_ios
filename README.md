# Daily Logger for iPhone

The iPhone version of [Daily Logger](https://github.com/kapild/daily_logger_calendar): writes your
sleep, workouts, places, drives and commutes to your calendar, with the same titles and tags as the
Android app, so history carries straight on.

| You see in the calendar | Comes from |
| --- | --- |
| `Sleep \| Dur: 6 hours 47 mins \| Start: 11:24 pm End: 6:29 am`, with stages in the notes | Apple Health (Withings, Apple Watch, ...) |
| `Run \| Dur: 32 mins \| ...` | Apple Health workouts |
| `Left home \| At: 8:02 am`, `Arrived office \| At: 9:01 am`, `At work \| Dur: ...` | iOS region monitoring of your saved places |
| `Commute to work by car \| Dur: 52 mins \| ...` | places plus car Bluetooth (a Shortcuts automation) or motion |
| `Work to home via shuttle and car`, `Commute home by shuttle`, `Drive` | the shuttle Wi-Fi automations plus the above |

This is step 1 (the logger). Widgets and the Insights tab come next.

## Quick start

1. On a Mac with Xcode 16: `brew install xcodegen`, then `xcodegen` in this folder.
2. Create `Config/Local.xcconfig` with `DEVELOPMENT_TEAM = <your team id>`.
3. Open `DailyLogger.xcodeproj`, pick your iPhone, press **Run**.
4. In the app's **Setup** tab: allow Health, Calendar, Location (**Always**) and Motion; pick the
   **Logger** calendar; set home, office and gym with **Use my current location**.
5. Create the 5 Shortcuts automations listed in **Setup**, each set to **Run Immediately**.

A free Apple account works, but the app stops after 7 days and Health may not wake it in the
background; the $99 developer account avoids both. Details below.

## How it works on iPhone

iOS doesn't let an app run all the time, so Daily Logger is woken up and catches up each time:

- **Entering or leaving a saved place.** iOS starts the app in the background, even if it was closed.
- **Shortcuts automations** for Wi-Fi (shuttle on and off, home and office) and car Bluetooth. This is
  the only way iOS lets an app notice those.
- **New data in Apple Health**, for example when Withings syncs last night.
- **Background refresh** about hourly (iOS picks the time), and every time you open the app.

Each wake-up logs a signal and rebuilds the last two days of places events (and the last week of sleep
and workouts) in your calendar. Events are matched by the `[hc:...]` tag at the end of their notes, so
re-runs never duplicate. Places tags carry an `i` (`pl:trip:i12`) so they never collide with the Android
app's, and Android's events are never removed. A night the Android app already wrote isn't written again.

**Drives** come from the car Bluetooth automation. Until it has run once, the phone's motion sensor is
used instead (iOS keeps a week of motion history), except during shuttle rides.

## Setup

You need a Mac with Xcode 16, and ideally the paid Apple Developer account: with a free account,
apps you install yourself stop working after 7 days, and HealthKit background delivery may not be
available.

1. `brew install xcodegen`, then in this folder run `xcodegen`. It creates `DailyLogger.xcodeproj`.
2. Create `Config/Local.xcconfig` with your team id (Xcode › Settings › Accounts):
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   DL_BUNDLE_ID = dev.kapil.dailylogger
   ```
   With a free account the bundle id must be unique; change it if Xcode complains.
3. Open the project, pick your iPhone, press **Run**.
4. On the phone, add your Google account if the Logger calendar isn't listed: **Settings › Apps ›
   Calendar › Calendar Accounts**.
5. In the app, **Setup**:
   1. Allow Apple Health, Calendar, Location (choose **Always**) and Motion.
   2. Pick the **Logger** calendar.
   3. Stand at home, office and gym in turn and tap **Use my current location** for each. Add their
      Wi-Fi names if you like.
   4. Check the shuttle Wi-Fi name (`GBUS`).
6. Create the Shortcuts automations (**Setup › 4**), each set to **Run Immediately**:

   | When | Do |
   | --- | --- |
   | Wi-Fi `GBUS` joins | Log: Joined Wi-Fi, `GBUS` |
   | Wi-Fi `GBUS` leaves | Log: Left Wi-Fi, `GBUS` |
   | Bluetooth: your car is connected | Log: Car connected |
   | Bluetooth: your car is disconnected | Log: Car disconnected |
   | Wi-Fi home / office joins (one each) | Log: Joined Wi-Fi, with the name |

The **Found** tab lists every signal (swipe to delete a wrong one); **Activity** shows what each sync did.

## First day: what to check

- Leave home with the app closed: a `Left home` event should appear within a few minutes.
- Get on the shuttle and connect the car: the Shortcuts actions should run without opening the app
  (they show in the **Found** tab).
- Next morning, last night's sleep should be in the calendar once Health has it.

If something is missing, the **Activity** tab shows what each sync did.

## Code

| Path | What |
| --- | --- |
| `LoggerCore/` | The rules, no iOS frameworks: `PlaceTimeline` and `PlacesBuilder` (ported line for line from Android), `SignalRules`, `Format`, sleep and workout events, `Reconcile`. Tested on Linux in CI. |
| `App/Sources/` | The iPhone app: `PlaceMonitor` (regions), `Intents` (Shortcuts actions), `MotionDrives`, `HealthSource`, `CalendarStore` (EventKit), `SyncCoordinator`, and the screens. |
| `project.yml` | XcodeGen spec for the Xcode project. |

CI tests `LoggerCore` on Linux and builds the app for the simulator on macOS. Run the tests locally
with `cd LoggerCore && swift test`.

## Not yet tested on a phone

CI only proves it compiles and the rules pass. Unconfirmed until you run it: background wake-ups from
regions and Health, Shortcuts actions running without opening the app, and writing to a Google calendar
through iOS.
