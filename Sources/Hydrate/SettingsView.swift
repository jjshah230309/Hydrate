import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: HydrateStore
    @Environment(\.dismiss) private var dismiss

    @State private var goalText   = ""
    @State private var goalUnit   = "ml"
    @State private var intervalMin = 30
    @State private var sipOn      = false
    @State private var sipText    = ""
    @State private var bottleOn   = false
    @State private var bottleText = ""
    @State private var invalidMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text("⚙  Settings")
                        .font(F.b(18)).foregroundStyle(P.textH)
                        .padding(.top, 22).padding(.bottom, 4)

                    goalCard
                    intervalCard
                    sipCard
                    bottleCard
                }
                .padding(.bottom, 12)
            }

            PillButton(title: "Save Settings", bg: P.primary, fg: .white,
                       font: F.b(14), vPad: 10, hPad: 12, action: save)
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)

            Text("Cancel")
                .font(F.r(12)).foregroundStyle(P.textS)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .padding(.bottom, 14)
        }
        .frame(width: 340, height: 620)
        .background(P.bg)
        .onAppear(perform: load)
        .alert("Invalid", isPresented: Binding(
            get: { invalidMessage != nil },
            set: { if !$0 { invalidMessage = nil } })
        ) {
            Button("OK") { invalidMessage = nil }
        } message: {
            Text(invalidMessage ?? "")
        }
    }

    private func load() {
        goalText    = "\(store.goalML)"
        goalUnit    = "ml"
        intervalMin = store.reminderMin
        sipOn       = store.sipEnabled
        sipText     = "\(store.sipML)"
        bottleOn    = store.bottleEnabled
        bottleText  = "\(store.bottleML)"
    }

    // ── Card chrome ──────────────────────────────────────────────────────────
    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        CardBox {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(F.b(13)).foregroundStyle(P.textH)
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
                content()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // ── Goal ─────────────────────────────────────────────────────────────────
    private var goalCard: some View {
        card("Daily Water Goal") {
            HStack(spacing: 8) {
                FlatField(placeholder: "", text: $goalText, width: 78)
                Picker("", selection: $goalUnit) {
                    ForEach(UNITS, id: \.self) { Text($0).font(F.r(12)) }
                }
                .labelsHidden().frame(width: 96)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            HStack(spacing: 6) {
                ForEach([("1.5 L", 1500), ("2 L", 2000), ("2.5 L", 2500), ("3 L", 3000)],
                        id: \.1) { label, val in
                    PillButton(title: label, bg: P.priLt, fg: P.primary,
                               vPad: 4, hPad: 8, fill: false) {
                        goalText = "\(val)"; goalUnit = "ml"
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    // ── Reminder interval ────────────────────────────────────────────────────
    private var intervalCard: some View {
        card("Reminder Interval") {
            HStack(spacing: 8) {
                Text("Every").font(F.r(12)).foregroundStyle(P.textB)
                Stepper(value: $intervalMin, in: 5...240, step: 5) {
                    Text("\(intervalMin)")
                        .font(F.r(13)).foregroundStyle(P.textB)
                        .frame(width: 34, alignment: .leading)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(P.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("minutes").font(F.r(12)).foregroundStyle(P.textB)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            HStack(spacing: 4) {
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in
                    PillButton(title: "\(m)m", bg: P.priLt, fg: P.primary,
                               vPad: 4, hPad: 7, fill: false) { intervalMin = m }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    // ── Sip ──────────────────────────────────────────────────────────────────
    private var sipCard: some View {
        card("💧  Sip Size") {
            Toggle(isOn: $sipOn) {
                Text("Enable sip logging").font(F.r(11)).foregroundStyle(P.textB)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 16).padding(.bottom, 8)

            HStack(spacing: 6) {
                Text("One sip =").font(F.r(12)).foregroundStyle(P.textB)
                FlatField(placeholder: "", text: $sipText, width: 60)
                Text("ml").font(F.r(12)).foregroundStyle(P.textB)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            HStack(spacing: 4) {
                ForEach([15, 20, 30, 50], id: \.self) { v in
                    PillButton(title: "\(v) ml", bg: P.sipLt, fg: P.sip,
                               vPad: 4, hPad: 7, fill: false) { sipText = "\(v)" }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    // ── Bottle ───────────────────────────────────────────────────────────────
    private var bottleCard: some View {
        card("🍶  My Bottle") {
            Toggle(isOn: $bottleOn) {
                Text("Enable bottle logging").font(F.r(11)).foregroundStyle(P.textB)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 16).padding(.bottom, 8)

            HStack(spacing: 6) {
                Text("Bottle =").font(F.r(12)).foregroundStyle(P.textB)
                FlatField(placeholder: "", text: $bottleText, width: 60)
                Text("ml").font(F.r(12)).foregroundStyle(P.textB)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            HStack(spacing: 6) {
                ForEach([("350 ml", 350), ("500 ml", 500), ("750 ml", 750), ("1 L", 1000)],
                        id: \.1) { label, val in
                    PillButton(title: label, bg: P.tealLt, fg: P.teal,
                               vPad: 4, hPad: 7, fill: false) { bottleText = "\(val)" }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    // ── Save ─────────────────────────────────────────────────────────────────
    private func save() {
        guard let g = Double(goalText.trimmingCharacters(in: .whitespaces)),
              case let goal = toML(g, goalUnit), goal > 0 else {
            invalidMessage = "Enter a positive goal."; return
        }
        guard let s = Int(sipText.trimmingCharacters(in: .whitespaces)), s > 0 else {
            invalidMessage = "Enter a valid sip size."; return
        }
        guard let b = Int(bottleText.trimmingCharacters(in: .whitespaces)), b > 0 else {
            invalidMessage = "Enter a valid bottle size."; return
        }

        store.goalML       = goal
        store.sipML        = s
        store.bottleML     = b
        store.reminderMin  = intervalMin
        store.sipEnabled   = sipOn
        store.bottleEnabled = bottleOn
        store.save()

        // Re-register the launch agent so the new interval takes effect.
        if store.reminderEnabled {
            Reminders.enable(intervalMin: intervalMin)
            store.reminderEnabledAt = Date().timeIntervalSince1970
            store.save()
        }
        dismiss()
    }
}
