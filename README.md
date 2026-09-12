# Hydrate

A native macOS water tracker — SwiftUI + AppKit, no Python, no third-party binaries.

This is a rewrite of the original Tk/py2app app (`~/Desktop/Desktop/HydrateBuild`).
It reads and writes the **same data file in the same format**, so no history was
migrated, converted, or lost.

## Build & install

```
./build.sh                                   # → build/Hydrate.app
cp -R build/Hydrate.app /Applications/       # install
```

Produces a universal (arm64 + x86_64) ad-hoc-signed bundle, ~4.6 MB.
Requires only the Xcode Command Line Tools. macOS 14+.

## Layout

| Path | Purpose |
|---|---|
| `Sources/Hydrate/Model.swift` | `HydrateStore` — loads/saves `~/.watertracker/data.json`, plus the unit conversions and formatters ported from the Python helpers |
| `Sources/Hydrate/Theme.swift` | Colour palette (`C` dict), Avenir Next typography, shared card/pill/field views |
| `Sources/Hydrate/ContentView.swift` | Main window: ring, stat pills, add-water card, reminder card, today's log |
| `Sources/Hydrate/HistoryView.swift` | History window: Day / Week / Month / Year, drill-in, edit-a-day |
| `Sources/Hydrate/SettingsView.swift` | Goal, reminder interval, sip and bottle settings |
| `Sources/Hydrate/ProgressRingView.swift` | The progress ring |
| `Sources/Hydrate/Reminders.swift` | launchd agent management (register, repair, disable) |
| `Sources/Hydrate/HydrateApp.swift` | App entry point and window-geometry persistence |
| `Sources/HydrateReminder/main.swift` | Reminder helper — nested app bundle launchd runs on a timer |

## Data

Everything lives in `~/.watertracker/data.json`, exactly as before:

```json
{ "today": "...", "intake_ml": 0, "log": [...], "goal_ml": 2500, "unit": "ml",
  "reminder_min": 15, "reminder_enabled": true, "reminder_enabled_at": 0.0,
  "bottle_enabled": true, "bottle_ml": 750, "sip_enabled": true, "sip_ml": 50,
  "history": { "YYYY-MM-DD": { "intake_ml": 0, "goal_ml": 0 } },
  "window_geometry": "WxH+X+Y", "window_fullscreen": false }
```

`Model.swift` hand-writes this JSON rather than using `JSONEncoder`, so the output
is byte-identical to Python's `json.dump(…, indent=2)` — same key order, same
two-space indent, same `\uXXXX` escaping. Keys the app doesn't model are read and
written back untouched, so nothing is dropped by a future schema change.

`window_geometry` keeps Tk's `WxH+X+Y` convention (Y measured down from the top of
the primary display) and is converted to and from an `NSRect` on the fly.

## Reminders

`Reminders.swift` registers a launchd agent — same label and plist path the Python
version used, `com.local.watertracker.reminder`, so it replaces the old job rather
than running alongside it.

The agent runs `HydrateReminder --fire` on an interval. That helper reads
`data.json`, bails out if reminders are off or the file is stale, and posts a
banner with live numbers ("950 ml to go · 62% of today's goal complete") via
`UNUserNotificationCenter`, falling back to an AppleScript banner if notification
permission was declined. Clicking a banner relaunches the helper with no arguments,
which opens Hydrate and exits.

**The old build hard-coded the app's path into the plist**, so moving `Hydrate.app`
silently broke reminders — which is what had happened: the agent still pointed at
`~/Desktop/Hydrate.app` after the app moved to `Desktop/Desktop/`, and
`~/.watertracker/notifier.log` had filled with "No such file" errors. Hydrate now
checks the recorded path, interval, and launchd registration at every launch and
re-registers the agent when any of them has drifted.
