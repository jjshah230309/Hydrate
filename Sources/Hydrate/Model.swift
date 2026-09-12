import Foundation

// ── Constants ────────────────────────────────────────────────────────────────
let GLASS_ML = 250
let UNITS = ["ml", "L", "glasses"]

struct QuickAdd {
    let label: String
    let ml: Int
    let bg: String
    let fg: String
}

let QUICK_ADDS = [
    QuickAdd(label: "100 ml", ml: 100, bg: "#E5DEFF", fg: "#6952B3"),
    QuickAdd(label: "250 ml", ml: 250, bg: "#C4DFEE", fg: "#2A6890"),
    QuickAdd(label: "500 ml", ml: 500, bg: "#BDE8D3", fg: "#2D8A60"),
    QuickAdd(label: "750 ml", ml: 750, bg: "#FFD9C0", fg: "#B85820"),
]

// ── Date helpers (ISO yyyy-MM-dd, matching Python's str(date.today())) ───────
enum DateKey {
    /// Fixed-format formatter — locale/timezone independent parsing of the
    /// "YYYY-MM-DD" keys the Python app wrote.
    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    static func string(_ d: Date) -> String { fmt.string(from: d) }
    static func date(_ s: String) -> Date? { fmt.date(from: s) }
    static var today: String { string(Date()) }
}

// ── Log entry ────────────────────────────────────────────────────────────────
struct LogEntry: Identifiable, Equatable {
    var id = UUID()
    var time: String
    var ml: Int
    var sip: Bool = false
    var bottle: Bool = false
}

struct HistoryEntry: Equatable {
    var intakeML: Int
    var goalML: Int
}

// ── Store ────────────────────────────────────────────────────────────────────
/// Reads and writes ~/.watertracker/data.json in exactly the format the
/// original Python app used, preserving key order and any unknown keys.
final class HydrateStore: ObservableObject {

    static let dataDir  = (NSHomeDirectory() as NSString).appendingPathComponent(".watertracker")
    static let dataFile = (dataDir as NSString).appendingPathComponent("data.json")

    @Published var today: String
    @Published var intakeML: Int
    @Published var log: [LogEntry]
    @Published var goalML: Int
    @Published var unit: String
    @Published var reminderMin: Int
    @Published var reminderEnabled: Bool
    @Published var reminderEnabledAt: Double
    @Published var bottleEnabled: Bool
    @Published var bottleML: Int
    @Published var sipEnabled: Bool
    @Published var sipML: Int
    @Published var history: [String: HistoryEntry]

    var windowGeometry: String?
    var windowFullscreen: Bool

    /// Any keys the original file had that this app does not model — written
    /// back out untouched so no data is ever lost.
    private var extras: [String: Any] = [:]

    // ── Load ─────────────────────────────────────────────────────────────────
    init() {
        // Defaults mirror load_data() in watertracker.py
        today             = DateKey.today
        intakeML          = 0
        log               = []
        goalML            = 2000
        unit              = "ml"
        reminderMin       = 30
        reminderEnabled   = false
        reminderEnabledAt = 0.0
        bottleEnabled     = false
        bottleML          = 500
        sipEnabled        = false
        sipML             = 30
        history           = [:]
        windowGeometry    = nil
        windowFullscreen  = false

        try? FileManager.default.createDirectory(
            atPath: Self.dataDir, withIntermediateDirectories: true)

        guard let data = FileManager.default.contents(atPath: Self.dataFile),
              let obj  = try? JSONSerialization.jsonObject(with: data),
              var d    = obj as? [String: Any]
        else { return }

        // New day → archive yesterday into history first (same as load_data)
        if (d["today"] as? String) != DateKey.today {
            let oldDate   = d["today"] as? String ?? ""
            let oldIntake = intOf(d["intake_ml"]) ?? 0
            let oldGoal   = intOf(d["goal_ml"]) ?? 2000
            if !oldDate.isEmpty {
                var hist = d["history"] as? [String: Any] ?? [:]
                hist[oldDate] = ["intake_ml": oldIntake, "goal_ml": oldGoal]
                d["history"] = hist
            }
            d["today"]     = DateKey.today
            d["intake_ml"] = 0
            d["log"]       = []
        }

        today             = d["today"] as? String ?? DateKey.today
        intakeML          = intOf(d["intake_ml"]) ?? 0
        goalML            = intOf(d["goal_ml"]) ?? 2000
        unit              = d["unit"] as? String ?? "ml"
        reminderMin       = intOf(d["reminder_min"]) ?? 30
        reminderEnabled   = boolOf(d["reminder_enabled"]) ?? false
        reminderEnabledAt = doubleOf(d["reminder_enabled_at"]) ?? 0.0
        bottleEnabled     = boolOf(d["bottle_enabled"]) ?? false
        bottleML          = intOf(d["bottle_ml"]) ?? 500
        sipEnabled        = boolOf(d["sip_enabled"]) ?? false
        sipML             = intOf(d["sip_ml"]) ?? 30
        windowGeometry    = d["window_geometry"] as? String
        windowFullscreen  = boolOf(d["window_fullscreen"]) ?? false

        if let rawLog = d["log"] as? [[String: Any]] {
            log = rawLog.map { e in
                LogEntry(time:   e["time"] as? String ?? "",
                         ml:     intOf(e["ml"]) ?? 0,
                         sip:    boolOf(e["sip"]) ?? false,
                         bottle: boolOf(e["bottle"]) ?? false)
            }
        }
        if let rawHist = d["history"] as? [String: Any] {
            for (k, v) in rawHist {
                guard let e = v as? [String: Any] else { continue }
                history[k] = HistoryEntry(intakeML: intOf(e["intake_ml"]) ?? 0,
                                          goalML:   intOf(e["goal_ml"]) ?? 2000)
            }
        }

        // Stash anything we don't model so save() can write it back verbatim.
        let known: Set<String> = ["today", "intake_ml", "log", "goal_ml", "unit",
            "reminder_min", "reminder_enabled", "reminder_enabled_at",
            "bottle_enabled", "bottle_ml", "sip_enabled", "sip_ml", "history",
            "window_geometry", "window_fullscreen"]
        for (k, v) in d where !known.contains(k) { extras[k] = v }
    }

    // JSON numbers arrive as NSNumber; coerce defensively.
    private func intOf(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String   { return Int(s) }
        return nil
    }
    private func doubleOf(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
    private func boolOf(_ v: Any?) -> Bool? {
        if let n = v as? NSNumber { return n.boolValue }
        return nil
    }

    // ── Save ─────────────────────────────────────────────────────────────────
    /// Writes today's snapshot into history — called on every change, exactly
    /// like archive_today() in the original.
    func archiveToday() {
        history[today] = HistoryEntry(intakeML: intakeML, goalML: goalML)
    }

    func save() {
        let json = serialize()
        let tmp  = Self.dataFile + ".tmp"
        do {
            try json.write(toFile: tmp, atomically: false, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(
                URL(fileURLWithPath: Self.dataFile),
                withItemAt: URL(fileURLWithPath: tmp))
        } catch {
            // Last resort: direct write
            try? json.write(toFile: Self.dataFile, atomically: true, encoding: .utf8)
        }
    }

    /// Hand-rolled writer so the output matches Python's json.dump(indent=2)
    /// byte for byte — same key order, same spacing. The file stays readable
    /// by the old Python app.
    private func serialize() -> String {
        var out = "{\n"
        var parts: [String] = []

        func esc(_ s: String) -> String {
            var r = ""
            for c in s.unicodeScalars {
                switch c {
                case "\"": r += "\\\""
                case "\\": r += "\\\\"
                case "\n": r += "\\n"
                case "\r": r += "\\r"
                case "\t": r += "\\t"
                default:
                    if c.value < 0x20 {
                        r += String(format: "\\u%04x", c.value)
                    } else if c.value > 0x7E {
                        // Python's json.dump defaults to ensure_ascii=True
                        if c.value > 0xFFFF {
                            let v = c.value - 0x10000
                            r += String(format: "\\u%04x\\u%04x",
                                        0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
                        } else {
                            r += String(format: "\\u%04x", c.value)
                        }
                    } else {
                        r.unicodeScalars.append(c)
                    }
                }
            }
            return r
        }
        func kv(_ k: String, _ v: String, indent: String = "  ") -> String {
            "\(indent)\"\(esc(k))\": \(v)"
        }

        parts.append(kv("today", "\"\(esc(today))\""))
        parts.append(kv("intake_ml", "\(intakeML)"))

        // log
        if log.isEmpty {
            parts.append(kv("log", "[]"))
        } else {
            var rows: [String] = []
            for e in log {
                var fields = ["      \"time\": \"\(esc(e.time))\"",
                              "      \"ml\": \(e.ml)"]
                if e.sip    { fields.append("      \"sip\": true") }
                if e.bottle { fields.append("      \"bottle\": true") }
                rows.append("    {\n" + fields.joined(separator: ",\n") + "\n    }")
            }
            parts.append(kv("log", "[\n" + rows.joined(separator: ",\n") + "\n  ]"))
        }

        parts.append(kv("goal_ml", "\(goalML)"))
        parts.append(kv("unit", "\"\(esc(unit))\""))
        parts.append(kv("reminder_min", "\(reminderMin)"))
        parts.append(kv("reminder_enabled", reminderEnabled ? "true" : "false"))
        parts.append(kv("reminder_enabled_at", "\(reminderEnabledAt)"))
        parts.append(kv("bottle_enabled", bottleEnabled ? "true" : "false"))
        parts.append(kv("bottle_ml", "\(bottleML)"))
        parts.append(kv("sip_enabled", sipEnabled ? "true" : "false"))
        parts.append(kv("sip_ml", "\(sipML)"))

        // history — sorted by date so the file stays stable and readable
        if history.isEmpty {
            parts.append(kv("history", "{}"))
        } else {
            var rows: [String] = []
            for k in history.keys.sorted() {
                let e = history[k]!
                rows.append("    \"\(esc(k))\": {\n"
                          + "      \"intake_ml\": \(e.intakeML),\n"
                          + "      \"goal_ml\": \(e.goalML)\n"
                          + "    }")
            }
            parts.append(kv("history", "{\n" + rows.joined(separator: ",\n") + "\n  }"))
        }

        if let g = windowGeometry {
            parts.append(kv("window_geometry", "\"\(esc(g))\""))
        } else {
            parts.append(kv("window_geometry", "null"))
        }
        parts.append(kv("window_fullscreen", windowFullscreen ? "true" : "false"))

        // Unknown keys, preserved with the same formatting as the rest
        for (k, v) in extras.sorted(by: { $0.key < $1.key }) {
            parts.append(kv(k, pyJSON(v, indent: 2, esc: esc)))
        }

        out += parts.joined(separator: ",\n")
        out += "\n}"
        return out
    }

    // ── Day rollover ─────────────────────────────────────────────────────────
    /// If the calendar day changed while the app was open, archive the old day
    /// and start fresh — the same transition load_data() performs at launch.
    @discardableResult
    func rolloverIfNeeded() -> Bool {
        let now = DateKey.today
        guard today != now else { return false }
        history[today] = HistoryEntry(intakeML: intakeML, goalML: goalML)
        today    = now
        intakeML = 0
        log      = []
        save()
        return true
    }

    // ── Mutations ────────────────────────────────────────────────────────────
    func add(_ ml: Int, sip: Bool = false, bottle: Bool = false) {
        intakeML += ml
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        log.append(LogEntry(time: f.string(from: Date()), ml: ml, sip: sip, bottle: bottle))
        archiveToday()
        save()
    }

    func removeEntry(at idx: Int) {
        guard log.indices.contains(idx) else { return }
        let removed = log[idx].ml
        log.remove(at: idx)
        intakeML = max(0, intakeML - removed)
        archiveToday()
        save()
    }

    func editEntry(at idx: Int, newML: Int) {
        guard log.indices.contains(idx) else { return }
        let old = log[idx].ml
        log[idx].ml = newML
        intakeML = max(0, intakeML - old + newML)
        archiveToday()
        save()
    }

    func resetDay() {
        intakeML = 0
        log = []
        archiveToday()
        save()
    }

    /// Set the total for an arbitrary day (used by History → Edit day).
    func setTotal(for day: Date, ml: Int) {
        let ds = DateKey.string(day)
        if ds == today {
            intakeML = ml
            archiveToday()
        } else if var e = history[ds] {
            e.intakeML = ml
            history[ds] = e
        } else {
            history[ds] = HistoryEntry(intakeML: ml, goalML: goalML)
        }
        save()
    }

    // ── Queries ──────────────────────────────────────────────────────────────
    /// Percent of goal for a day, or nil when there is no data.
    func pct(for day: Date) -> Int? {
        let ds = DateKey.string(day)
        let ml: Int, goal: Int
        if ds == today {
            ml = intakeML; goal = goalML
        } else if let e = history[ds] {
            ml = e.intakeML; goal = e.goalML
        } else {
            return nil
        }
        guard goal > 0 else { return 0 }
        return min(100, Int(Double(ml) / Double(goal) * 100))
    }

    func amounts(for day: Date) -> (ml: Int, goal: Int)? {
        let ds = DateKey.string(day)
        if ds == today { return (intakeML, goalML) }
        if let e = history[ds] { return (e.intakeML, e.goalML) }
        return nil
    }
}

// ── Conversions & formatting (ports of the Python helpers) ───────────────────
func toDisplay(_ ml: Int, _ unit: String) -> Double {
    if unit == "L"       { return Double(ml) / 1000 }
    if unit == "glasses" { return Double(ml) / Double(GLASS_ML) }
    return Double(ml)
}

func toML(_ val: Double, _ unit: String) -> Int {
    if unit == "L"       { return Int(val * 1000) }
    if unit == "glasses" { return Int(val * Double(GLASS_ML)) }
    return Int(val)
}

func fmt(_ ml: Int, _ unit: String) -> String {
    let v = toDisplay(ml, unit)
    if unit == "L"       { return String(format: "%.2f L", v) }
    if unit == "glasses" { return String(format: "%.1f gl", v) }
    return "\(Int(v)) ml"
}

func goalFmt(_ goalML: Int, _ unit: String) -> String {
    let v = toDisplay(goalML, unit)
    if unit == "L"       { return String(format: "%.1f L", v) }
    if unit == "glasses" { return "\(Int(v)) glasses" }
    return "\(Int(v)) ml"
}

func motivation(_ pct: Double) -> String {
    if pct == 0   { return "Let's start — your body is 60% water 🌊" }
    if pct < 25   { return "Nice start, keep the momentum going 🌱" }
    if pct < 50   { return "Getting there, don't stop now! ✨" }
    if pct < 75   { return "Over halfway — you're doing amazing! 🌟" }
    if pct < 100  { return "So close to your goal — finish strong! 💪" }
    return "Daily goal achieved! You're a hydration hero! 🏆"
}

func fmtCountdown(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    return h > 0 ? String(format: "%dh %02dm %02ds", h, m, sec)
                 : String(format: "%d:%02d", m, sec)
}

/// Value formatted for an editable text field, matching the Python dialogs.
func editString(_ ml: Int, _ unit: String) -> String {
    let d = toDisplay(ml, unit)
    if unit == "L"       { return String(format: "%.3f", d) }
    if unit == "glasses" { return String(format: "%.1f", d) }
    return "\(Int(d))"
}

/// Renders an arbitrary JSON value the way Python's json.dump(indent=2) would,
/// so keys this app doesn't model are written back in matching style.
private func pyJSON(_ value: Any, indent: Int, esc: (String) -> String) -> String {
    let pad = String(repeating: " ", count: indent)
    let padIn = String(repeating: " ", count: indent + 2)

    switch value {
    case let s as String:
        return "\"\(esc(s))\""
    case let n as NSNumber:
        // Distinguish Bool from numeric NSNumber
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
        if CFNumberIsFloatType(n) { return "\(n.doubleValue)" }
        return "\(n.intValue)"
    case let a as [Any]:
        if a.isEmpty { return "[]" }
        let items = a.map { padIn + pyJSON($0, indent: indent + 2, esc: esc) }
        return "[\n" + items.joined(separator: ",\n") + "\n" + pad + "]"
    case let d as [String: Any]:
        if d.isEmpty { return "{}" }
        let items = d.keys.sorted().map { k in
            padIn + "\"\(esc(k))\": " + pyJSON(d[k]!, indent: indent + 2, esc: esc)
        }
        return "{\n" + items.joined(separator: ",\n") + "\n" + pad + "}"
    default:
        return "null"
    }
}
