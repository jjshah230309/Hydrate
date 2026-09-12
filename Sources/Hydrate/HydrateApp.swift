import SwiftUI
import AppKit

@main
struct HydrateApp: App {
    @StateObject private var store = HydrateStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Hydrate", id: "main") {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    delegate.store = store
                    // The old build baked the app's path into the launch agent,
                    // so moving Hydrate.app broke reminders silently. Re-point it.
                    Reminders.repairIfNeeded(enabled: store.reminderEnabled,
                                             intervalMin: store.reminderMin)
                }
        }
        .defaultSize(width: 390, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            HistoryCommand()
        }

        Window("History", id: "history") {
            HistoryView().environmentObject(store)
        }
        .defaultSize(width: 420, height: 480)
    }
}

/// Adds ⌘Y to reopen the History window from the menu bar.
struct HistoryCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("History") { openWindow(id: "history") }
                .keyboardShortcut("y", modifiers: .command)
        }
    }
}

// ── Window geometry persistence ──────────────────────────────────────────────
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: HydrateStore?
    private var saveWork: DispatchWorkItem?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Let the window exist before positioning it.
        DispatchQueue.main.async { [weak self] in self?.attachToMainWindow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ n: Notification) { saveGeometry() }

    private func attachToMainWindow(retries: Int = 20) {
        guard let w = NSApp.windows.first(where: { $0.title == "Hydrate" }) else {
            // The scene may not have materialised yet — try again shortly.
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.attachToMainWindow(retries: retries - 1)
                }
            }
            return
        }
        mainWindow = w
        w.minSize = NSSize(width: 360, height: 620)
        // Own the frame ourselves; AppKit's autosave would fight the value we
        // keep in data.json.
        w.setFrameAutosaveName("")

        applySavedFrame(to: w)

        // SwiftUI positions the window on its own just after this runs, so put
        // our frame back once it has settled — and only then start recording
        // moves, otherwise we would persist SwiftUI's placement over the
        // user's saved position.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.applySavedFrame(to: w)

            if self.store?.windowFullscreen == true, !w.styleMask.contains(.fullScreen) {
                w.toggleFullScreen(nil)
            }

            let nc = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.didEnterFullScreenNotification,
                         NSWindow.didExitFullScreenNotification] {
                nc.addObserver(self, selector: #selector(self.windowChanged(_:)),
                               name: name, object: w)
            }
        }
    }

    private func applySavedFrame(to w: NSWindow) {
        if let geo = store?.windowGeometry, let frame = Self.frame(fromTk: geo) {
            w.setFrame(frame, display: true)
        } else if let screen = w.screen ?? NSScreen.main {
            // No saved position — centre at the default size, as the old app did.
            let size = NSSize(width: 390, height: 860)
            let f = screen.frame
            w.setFrame(NSRect(x: f.midX - size.width / 2,
                              y: f.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        }
    }

    @objc private func windowChanged(_ n: Notification) {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveGeometry() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveGeometry() {
        guard let store, let w = mainWindow else { return }
        let full = w.styleMask.contains(.fullScreen)
        store.windowFullscreen = full
        if !full { store.windowGeometry = Self.tkString(from: w.frame) }
        store.save()
    }

    // ── Tk "WxH+X+Y" ⇄ NSRect ────────────────────────────────────────────────
    // Tk measures Y downward from the top of the primary display; AppKit
    // measures upward from its bottom. Keeping the same string means the old
    // Python app could still read the file.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 900
    }

    static func tkString(from frame: NSRect) -> String {
        let x = Int(frame.origin.x.rounded())
        let y = Int((primaryHeight - frame.origin.y - frame.height).rounded())
        return "\(Int(frame.width.rounded()))x\(Int(frame.height.rounded()))+\(x)+\(y)"
    }

    static func frame(fromTk s: String) -> NSRect? {
        // WxH+X+Y  (X and Y may be negative)
        let scanner = Scanner(string: s)
        guard let w = scanner.scanInt(), scanner.scanString("x") != nil,
              let h = scanner.scanInt() else { return nil }
        guard let x = scanner.scanInt(), let y = scanner.scanInt() else { return nil }
        guard w > 0, h > 0 else { return nil }

        let originY = primaryHeight - CGFloat(y) - CGFloat(h)
        let rect = NSRect(x: CGFloat(x), y: originY, width: CGFloat(w), height: CGFloat(h))

        // Sanity check — only restore if it lands on a screen we actually have.
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(rect) }
        return onScreen ? rect : nil
    }
}
