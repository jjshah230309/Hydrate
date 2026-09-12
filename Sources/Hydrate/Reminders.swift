import Foundation

/// Manages the launchd agent that fires hydration reminders even when the app
/// is closed. Same label and plist path the Python version used, so switching
/// over replaces the old agent rather than adding a second one.
enum Reminders {

    static let label = "com.local.watertracker.reminder"

    static var plistPath: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var logPath: String {
        (HydrateStore.dataDir as NSString).appendingPathComponent("notifier.log")
    }

    /// The bundled reminder helper: Hydrate.app/Contents/Library/HydrateReminder.app
    static var helperPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HydrateReminder.app/Contents/MacOS/HydrateReminder")
            .path
    }

    private static var uid: String { "\(getuid())" }

    // ── Registration ─────────────────────────────────────────────────────────
    static func enable(intervalMin: Int) {
        writePlist(intervalMin: intervalMin)
        run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
        // Fire one immediately so the user sees that reminders are live.
        fireNow()
    }

    static func disable() {
        run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
    }

    static func fireNow() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: helperPath)
        p.arguments = ["--fire"]
        try? p.run()
    }

    // ── Self-healing ─────────────────────────────────────────────────────────
    /// The old build hard-coded the app's path into the launch agent, so moving
    /// Hydrate.app silently broke reminders. Re-register whenever the recorded
    /// path or interval no longer matches reality.
    static func repairIfNeeded(enabled: Bool, intervalMin: Int) {
        guard enabled else { return }
        guard FileManager.default.isExecutableFile(atPath: helperPath) else { return }

        var needsRewrite = true
        if let data = FileManager.default.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
           let args = plist["ProgramArguments"] as? [String],
           let interval = plist["StartInterval"] as? Int {
            needsRewrite = (args.first != helperPath)
                        || !args.contains("--fire")
                        || (interval != intervalMin * 60)
        }

        // Also re-register if launchd has no record of the job at all.
        if !needsRewrite && !isLoaded() { needsRewrite = true }

        if needsRewrite {
            writePlist(intervalMin: intervalMin)
            run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
            run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
        }
    }

    static func isLoaded() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "gui/\(uid)/\(label)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    // ── Plist ────────────────────────────────────────────────────────────────
    private static func writePlist(intervalMin: Int) {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [helperPath, "--fire"],
            "StartInterval": intervalMin * 60,
            "RunAtLoad": false,
            "StandardErrorPath": logPath,
        ]
        if let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: URL(fileURLWithPath: plistPath))
        }
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
