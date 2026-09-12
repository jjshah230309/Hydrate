import AppKit
import UserNotifications

// Native replacement for notifier.py + terminal-notifier.
//
//   HydrateReminder --fire   → launchd's periodic run: read the data file and
//                              post a reminder banner with live numbers.
//   HydrateReminder          → the user clicked a banner: bring Hydrate up.

let MAIN_BUNDLE_ID = "com.local.hydration-tracker"
let DATA_FILE = (NSHomeDirectory() as NSString)
    .appendingPathComponent(".watertracker/data.json")

// ── Locate Hydrate.app (we live at Hydrate.app/Contents/Library/HydrateReminder.app) ──
func mainAppURL() -> URL? {
    var url = Bundle.main.bundleURL
    for _ in 0..<3 { url = url.deletingLastPathComponent() }   // → Hydrate.app
    if url.pathExtension == "app", FileManager.default.fileExists(atPath: url.path) {
        return url
    }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: MAIN_BUNDLE_ID)
}

func openMainApp() {
    guard let url = mainAppURL() else { return }
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: cfg)
}

// ── Build the reminder text from today's data ────────────────────────────────
struct Reminder { let title: String; let body: String }

func buildReminder() -> Reminder? {
    guard let data = FileManager.default.contents(atPath: DATA_FILE),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let d = obj as? [String: Any] else { return nil }

    // Same two guards notifier.py applied: reminders on, and data is current.
    guard (d["reminder_enabled"] as? NSNumber)?.boolValue == true else { return nil }

    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    guard (d["today"] as? String) == f.string(from: Date()) else { return nil }

    let intake = (d["intake_ml"] as? NSNumber)?.intValue ?? 0
    let goal   = (d["goal_ml"] as? NSNumber)?.intValue ?? 2000
    let pct    = goal > 0 ? Int(Double(intake) / Double(goal) * 100) : 0

    let body: String
    if pct >= 100 {
        body = "Goal reached! You've had \(intake) ml today. Amazing work!"
    } else {
        body = "\(goal - intake) ml to go  ·  \(pct)% of today's goal complete."
    }
    return Reminder(title: "💧 Time to Drink Water!", body: body)
}

// ── Fallback: AppleScript banner, used when notifications aren't authorised ──
func postViaAppleScript(_ r: Reminder) {
    func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
    let script = "display notification \"\(esc(r.body))\" with title \"\(esc(r.title))\" sound name \"Blow\""
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    try? p.run()
    p.waitUntilExit()
}

// ── App delegate ─────────────────────────────────────────────────────────────
final class Delegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    let firing = CommandLine.arguments.contains("--fire")

    func applicationDidFinishLaunching(_ note: Notification) {
        UNUserNotificationCenter.current().delegate = self

        guard firing else {
            // Launched by a banner click (or by hand) — just show the app.
            openMainApp()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
            return
        }

        guard let reminder = buildReminder() else {
            NSApp.terminate(nil); return
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body  = reminder.body
                content.sound = UNNotificationSound(named: UNNotificationSoundName("Blow.aiff"))

                let req = UNNotificationRequest(
                    identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(req) { error in
                    if error != nil { postViaAppleScript(reminder) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        NSApp.terminate(nil)
                    }
                }
            } else {
                // Denied or undetermined in a background session — still notify.
                postViaAppleScript(reminder)
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }

        // Safety net: never linger.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { NSApp.terminate(nil) }
    }

    // Banner clicked while this helper is still alive.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        openMainApp()
        completionHandler()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
    }

    // Show the banner even if the helper happens to be frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
