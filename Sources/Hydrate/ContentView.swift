import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: HydrateStore
    @Environment(\.openWindow) private var openWindow

    @State private var amount = ""
    @State private var showSettings = false
    @State private var showResetConfirm = false
    @State private var invalidMessage: String?
    @State private var editingIndex: Int?
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// "Monday, August 31" — the same shape as the original's strftime("%A, %B %d").
    private static let dateLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMMM dd"
        return f
    }()

    private var pct: Double {
        store.goalML > 0 ? min(100, Double(store.intakeML) / Double(store.goalML) * 100) : 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                dateLabel
                ProgressRingView(pct: pct,
                                 main: ringMain,
                                 unit: store.unit,
                                 goal: "of \(goalFmt(store.goalML, store.unit))")
                    .padding(.top, 14)
                statPills
                addWaterCard
                reminderCard
                motivationLabel
                logCard
            }
            .frame(maxWidth: .infinity)
        }
        .background(P.bg)
        .frame(minWidth: 360, minHeight: 620)
        .onReceive(tick) { t in
            now = t
            // Roll the day over if the app was left open past midnight.
            if store.rolloverIfNeeded() { amount = "" }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
        .sheet(item: Binding(
            get: { editingIndex.map { IdentifiableInt(value: $0) } },
            set: { editingIndex = $0?.value })
        ) { wrapped in
            EditEntrySheet(index: wrapped.value).environmentObject(store)
        }
        .alert("Reset", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { store.resetDay() }
        } message: {
            Text("Reset today's intake to zero?")
        }
        .alert("Invalid", isPresented: Binding(
            get: { invalidMessage != nil },
            set: { if !$0 { invalidMessage = nil } })
        ) {
            Button("OK") { invalidMessage = nil }
        } message: {
            Text(invalidMessage ?? "")
        }
    }

    // ── Header ───────────────────────────────────────────────────────────────
    private var header: some View {
        HStack {
            Text("💧  Hydration Tracker")
                .font(F.b(20))
                .foregroundStyle(P.textH)
            Spacer()
            GlyphButton(glyph: "📅", size: 17) { openWindow(id: "history") }
            GlyphButton(glyph: "⚙", size: 17) { showSettings = true }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    private var dateLabel: some View {
        Text(Self.dateLabelFormatter.string(from: now))
            .font(F.r(12))
            .foregroundStyle(P.textS)
            .padding(.top, 2)
    }

    private var ringMain: String {
        let v = toDisplay(store.intakeML, store.unit)
        if store.unit == "L"       { return String(format: "%.2f", v) }
        if store.unit == "glasses" { return String(format: "%.1f", v) }
        return "\(Int(v))"
    }

    // ── Stat pills ───────────────────────────────────────────────────────────
    private var statPills: some View {
        HStack(spacing: 8) {
            statPill("\(Int(pct))%", "complete")
            statPill(String(format: "%.1f", Double(store.intakeML) / Double(GLASS_ML)), "glasses")
            statPill(fmt(max(0, store.goalML - store.intakeML), store.unit), "remaining")
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    private func statPill(_ value: String, _ label: String) -> some View {
        CardBox {
            VStack(spacing: 0) {
                Text(value).font(F.b(16)).foregroundStyle(P.textH).padding(.top, 9)
                Text(label).font(F.r(10)).foregroundStyle(P.textS).padding(.bottom, 9)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // ── Add water ────────────────────────────────────────────────────────────
    private var addWaterCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add Water")
                    .font(F.b(13)).foregroundStyle(P.textH)
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

                HStack(spacing: 6) {
                    ForEach(QUICK_ADDS, id: \.ml) { q in
                        PillButton(title: q.label,
                                   bg: Color(hex: q.bg), fg: Color(hex: q.fg)) {
                            store.add(q.ml)
                        }
                    }
                }
                .padding(.horizontal, 16)

                if store.sipEnabled && store.sipML > 0 {
                    PillButton(title: "💧  1 Sip  ·  \(store.sipML) ml",
                               bg: P.sipLt, fg: P.sip, font: F.b(12)) {
                        store.add(store.sipML, sip: true)
                    }
                    .padding(.horizontal, 19).padding(.top, 8)
                }

                if store.bottleEnabled && store.bottleML > 0 {
                    PillButton(title: "🍶  1 Bottle  ·  \(store.bottleML) ml",
                               bg: P.tealLt, fg: P.teal, font: F.b(12)) {
                        store.add(store.bottleML, bottle: true)
                    }
                    .padding(.horizontal, 19).padding(.top, 8)
                }

                HStack(spacing: 8) {
                    FlatField(placeholder: "Amount", text: $amount, width: 78,
                              onSubmit: addCustom)
                    Picker("", selection: $store.unit) {
                        ForEach(UNITS, id: \.self) { Text($0).font(F.r(12)) }
                    }
                    .labelsHidden()
                    .frame(width: 96)
                    .onChange(of: store.unit) { _, _ in store.save() }

                    PillButton(title: "Add +", bg: P.primary, fg: .white,
                               font: F.b(12), vPad: 8, hPad: 12, fill: false,
                               action: addCustom)
                    Spacer(minLength: 0)
                    PillButton(title: "Reset day", bg: P.border, fg: P.textS,
                               font: F.b(11), vPad: 8, hPad: 12, fill: false) {
                        showResetConfirm = true
                    }
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private func addCustom() {
        let raw = amount.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        guard let v = Double(raw) else {
            invalidMessage = "Please enter a positive number."; return
        }
        let ml = toML(v, store.unit)
        guard ml > 0 else {
            invalidMessage = "Please enter a positive number."; return
        }
        amount = ""
        store.add(ml)
    }

    // ── Reminder ─────────────────────────────────────────────────────────────
    private var reminderCard: some View {
        CardBox {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("🔔").font(F.r(16))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.reminderEnabled ? "Reminders active" : "Reminders off")
                            .font(F.b(13)).foregroundStyle(P.textH)
                        Text(store.reminderEnabled
                             ? "Every \(store.reminderMin) min  ·  runs even when closed"
                             : "Tap Start — persists when app is closed")
                            .font(F.r(11)).foregroundStyle(P.textS)
                    }
                    Spacer()
                    Text(store.reminderEnabled ? "Stop" : "Start")
                        .font(F.b(13))
                        .foregroundStyle(store.reminderEnabled ? P.peach : P.mint)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: toggleReminder)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)

                if store.reminderEnabled {
                    Text("⏱  Next reminder in  \(countdownText)")
                        .font(F.b(12)).foregroundStyle(P.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(P.card2)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    /// Time until the next launchd firing, derived the same way the Python
    /// `_tick` did: from when reminders were switched on plus whole intervals.
    private var countdownText: String {
        let ea = store.reminderEnabledAt == 0 ? now.timeIntervalSince1970 : store.reminderEnabledAt
        let ivl = Double(store.reminderMin) * 60
        let t = now.timeIntervalSince1970
        let cycles = floor(max(0, t - ea) / ivl)
        return fmtCountdown(max(0, ea + (cycles + 1) * ivl - t))
    }

    private func toggleReminder() {
        if store.reminderEnabled {
            Reminders.disable()
            store.reminderEnabled = false
            store.reminderEnabledAt = 0
        } else {
            Reminders.enable(intervalMin: store.reminderMin)
            store.reminderEnabled = true
            store.reminderEnabledAt = Date().timeIntervalSince1970
        }
        store.save()
    }

    private var motivationLabel: some View {
        Text(motivation(pct))
            .font(F.i(12))
            .foregroundStyle(P.textS)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 350)
            .padding(.top, 10).padding(.bottom, 6)
    }

    // ── Today's log ──────────────────────────────────────────────────────────
    private var logCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today's Log")
                    .font(F.b(13)).foregroundStyle(P.textH)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)

                if store.log.isEmpty {
                    Text("No entries yet today")
                        .font(F.r(11)).foregroundStyle(P.textS)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.bottom, 12)
                } else {
                    VStack(spacing: 4) {
                        ForEach(Array(store.log.enumerated().reversed()), id: \.element.id) { idx, e in
                            logRow(index: idx, entry: e, displayNumber: idx + 1)
                        }
                    }
                    .padding(.horizontal, 16)

                    Rectangle().fill(P.border).frame(height: 1)
                        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)

                    HStack {
                        Text("Total today").font(F.r(11)).foregroundStyle(P.textS)
                        Spacer()
                        Text(fmt(store.intakeML, store.unit))
                            .font(F.b(11)).foregroundStyle(P.textH)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    private func logRow(index: Int, entry: LogEntry, displayNumber: Int) -> some View {
        HStack(spacing: 0) {
            Text("#\(displayNumber)")
                .font(F.r(10)).foregroundStyle(P.textS)
                .frame(width: 26, alignment: .leading)
            Text(entry.time).font(F.r(11)).foregroundStyle(P.textS).padding(.leading, 4)
            Text(entry.sip ? "💧" : entry.bottle ? "🍶" : "·")
                .font(F.r(10)).padding(.horizontal, 4)
            Spacer(minLength: 8)
            GlyphButton(glyph: "✎", size: 12, base: P.textS, hover: P.primary) {
                editingIndex = index
            }
            GlyphButton(glyph: "×", size: 13, base: P.textS, hover: P.peach) {
                store.removeEntry(at: index)
            }
            Text(fmt(entry.ml, store.unit))
                .font(F.b(11)).foregroundStyle(P.primary)
                .padding(.trailing, 4)
        }
    }
}

// Small wrapper so `.sheet(item:)` can carry an Int index.
struct IdentifiableInt: Identifiable {
    let value: Int
    var id: Int { value }
}

// ── Edit a single log entry ──────────────────────────────────────────────────
struct EditEntrySheet: View {
    @EnvironmentObject var store: HydrateStore
    @Environment(\.dismiss) private var dismiss
    let index: Int

    @State private var text = ""
    @State private var invalid = false

    private var entry: LogEntry? { store.log.indices.contains(index) ? store.log[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            Text("Entry #\(index + 1)  ·  \(entry?.time ?? "")")
                .font(F.b(13)).foregroundStyle(P.textH)
                .padding(.top, 20).padding(.bottom, 8)

            HStack(spacing: 8) {
                FlatField(placeholder: "", text: $text, width: 90, font: F.r(14), onSubmit: save)
                Text(store.unit).font(F.r(13)).foregroundStyle(P.textB)
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                PillButton(title: "Save", bg: P.primary, fg: .white,
                           font: F.b(12), vPad: 8, hPad: 16, fill: false, action: save)
                PillButton(title: "Cancel", bg: P.border, fg: P.textS,
                           font: F.b(12), vPad: 8, hPad: 16, fill: false) { dismiss() }
            }
            .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .frame(width: 300, height: 210)
        .background(P.bg)
        .onAppear { text = editString(entry?.ml ?? 0, store.unit) }
        .alert("Invalid", isPresented: $invalid) {
            Button("OK") {}
        } message: {
            Text("Please enter a positive number.")
        }
    }

    private func save() {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)) else { invalid = true; return }
        let ml = toML(v, store.unit)
        guard ml > 0 else { invalid = true; return }
        store.editEntry(at: index, newML: ml)
        dismiss()
    }
}
