import SwiftUI
import AppKit

// ── Calendar helpers ─────────────────────────────────────────────────────────
enum Cal {
    /// Monday-first calendar, matching Python's `calendar.monthcalendar`.
    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2          // Monday
        c.timeZone = TimeZone.current
        return c
    }()

    static func startOfDay(_ d: Date) -> Date { cal.startOfDay(for: d) }

    static func adding(_ d: Date, days: Int) -> Date {
        cal.date(byAdding: .day, value: days, to: d) ?? d
    }
    static func adding(_ d: Date, months: Int) -> Date {
        cal.date(byAdding: .month, value: months, to: d) ?? d
    }
    static func adding(_ d: Date, years: Int) -> Date {
        cal.date(byAdding: .year, value: years, to: d) ?? d
    }

    static func ymd(_ d: Date) -> (y: Int, m: Int, d: Int) {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return (c.year!, c.month!, c.day!)
    }

    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
    }

    static func daysInMonth(_ y: Int, _ m: Int) -> Int {
        cal.range(of: .day, in: .month, for: date(y, m, 1))?.count ?? 30
    }

    /// 0 = Monday … 6 = Sunday
    static func weekdayIndex(_ d: Date) -> Int {
        (cal.component(.weekday, from: d) + 5) % 7
    }

    /// Monday of the week containing `d`.
    static func mondayOf(_ d: Date) -> Date {
        adding(startOfDay(d), days: -weekdayIndex(d))
    }

    /// Weeks of a month as Monday-first rows; 0 means "no day here".
    static func monthGrid(_ y: Int, _ m: Int) -> [[Int]] {
        let first = date(y, m, 1)
        let lead = weekdayIndex(first)
        let count = daysInMonth(y, m)
        var cells = Array(repeating: 0, count: lead) + Array(1...count)
        while cells.count % 7 != 0 { cells.append(0) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0+7]) }
    }

    static func fmt(_ d: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = cal
        f.dateFormat = pattern
        return f.string(from: d)
    }
}

// ── Scroll-wheel swipe capture (ports the trackpad nav from the Tk canvas) ───
struct ScrollCatcher: NSViewRepresentable {
    var onScroll: (CGFloat, CGFloat) -> Void

    final class CatcherView: NSView {
        var onScroll: ((CGFloat, CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaY, event.scrollingDeltaX)
        }
        override var acceptsFirstResponder: Bool { true }
    }

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onScroll = onScroll
        return v
    }
    func updateNSView(_ v: CatcherView, context: Context) { v.onScroll = onScroll }
}

// ── History window ───────────────────────────────────────────────────────────
struct HistoryView: View {
    @EnvironmentObject var store: HydrateStore

    enum ViewMode: String, CaseIterable { case day = "Day", week = "Week",
                                              case_month = "Month", year = "Year"
        var title: String {
            switch self {
            case .day: return "Day"
            case .week: return "Week"
            case .case_month: return "Month"
            case .year: return "Year"
            }
        }
    }

    @State private var mode: ViewMode
    @State private var anchor: Date         // navigation anchor
    @State private var selected: Date       // selected day (day view)

    init(initialMode: ViewMode = .case_month, anchoredAt: Date = Date()) {
        _mode = State(initialValue: initialMode)
        _anchor = State(initialValue: anchoredAt)
        _selected = State(initialValue: anchoredAt)
    }

    @State private var direction = 1        // slide direction
    @State private var editingDay: Date?
    @State private var swipeV: CGFloat = 0
    @State private var swipeH: CGFloat = 0

    private let swipeThreshold: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            header
            viewSelector
            navRow

            ZStack {
                ScrollCatcher(onScroll: handleScroll)
                content
                    .id("\(mode.rawValue)-\(DateKey.string(anchor))-\(DateKey.string(selected))")
                    .transition(.asymmetric(
                        insertion: .move(edge: direction == 1 ? .trailing : .leading),
                        removal:   .move(edge: direction == 1 ? .leading : .trailing)))
            }
            .clipped()
            .padding(.horizontal, 20)
            .padding(.top, 8).padding(.bottom, 8)

            legend
        }
        .background(P.bg)
        .frame(minWidth: 420, minHeight: 480)
        .sheet(item: Binding(
            get: { editingDay.map { DayBox(day: $0) } },
            set: { editingDay = $0?.day })
        ) { box in
            EditDaySheet(day: box.day).environmentObject(store)
        }
    }

    // ── Chrome ───────────────────────────────────────────────────────────────
    private var header: some View {
        HStack {
            Text("📅  History").font(F.b(18)).foregroundStyle(P.textH)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 18)
    }

    private var viewSelector: some View {
        HStack(spacing: 6) {
            ForEach(ViewMode.allCases, id: \.self) { v in
                Text(v.title)
                    .font(F.b(12))
                    .foregroundStyle(mode == v ? .white : P.primary)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(mode == v ? P.primary : P.priLt)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { goToToday(v) }
                    .onTapGesture { setMode(v) }
            }
        }
        .padding(.top, 12)
    }

    private var navRow: some View {
        HStack {
            GlyphButton(glyph: "◀", size: 14, base: P.primary, hover: P.priDk) { navigate(-1) }
            Spacer()
            Text(navLabel).font(F.b(13)).foregroundStyle(P.textH)
            Spacer()
            GlyphButton(glyph: "▶", size: 14, base: P.primary, hover: P.priDk) { navigate(1) }
        }
        .padding(.horizontal, 20).padding(.top, 10)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            ForEach([("No data", P.calNone), ("< 25%", P.calLow), ("50%", P.cal50),
                     ("75%", P.cal75), ("100%", P.cal100)], id: \.0) { label, color in
                Rectangle().fill(color).frame(width: 12, height: 12).padding(.leading, 8)
                Text(label).font(F.r(9)).foregroundStyle(P.textS).padding(.trailing, 4)
            }
        }
        .padding(.bottom, 12)
    }

    private var navLabel: String {
        switch mode {
        case .day:
            let d = selected
            return "\(Cal.fmt(d, "EEEE, MMMM")) \(Cal.ymd(d).d) \(Cal.ymd(d).y)"
        case .week:
            let mon = Cal.mondayOf(anchor)
            let sun = Cal.adding(mon, days: 6)
            return "\(Cal.fmt(mon, "MMM dd")) – \(Cal.fmt(sun, "MMM dd, yyyy"))"
        case .case_month:
            return Cal.fmt(anchor, "MMMM yyyy")
        case .year:
            return "\(Cal.ymd(anchor).y)"
        }
    }

    // ── Navigation ───────────────────────────────────────────────────────────
    private func setMode(_ v: ViewMode) {
        guard v != mode else { return }
        let order = ViewMode.allCases
        let dir = (order.firstIndex(of: v)! > order.firstIndex(of: mode)!) ? 1 : -1
        direction = dir
        withAnimation(.easeInOut(duration: 0.18)) { mode = v }
    }

    private func goToToday(_ v: ViewMode) {
        let today = Date()
        direction = Cal.startOfDay(anchor) < Cal.startOfDay(today) ? 1 : -1
        withAnimation(.easeInOut(duration: 0.18)) {
            mode = v
            anchor = today
            selected = today
        }
    }

    private func navigate(_ dir: Int) {
        direction = dir
        withAnimation(.easeInOut(duration: 0.18)) {
            switch mode {
            case .day:
                anchor = Cal.adding(anchor, days: dir); selected = anchor
            case .week:
                anchor = Cal.adding(anchor, days: 7 * dir)
            case .case_month:
                anchor = Cal.adding(anchor, months: dir)
            case .year:
                anchor = Cal.adding(anchor, years: dir)
            }
        }
    }

    private func handleScroll(_ dy: CGFloat, _ dx: CGFloat) {
        swipeV += dy
        swipeH += dx
        if swipeV > swipeThreshold      { swipeV = 0; navigate(-1) }
        else if swipeV < -swipeThreshold { swipeV = 0; navigate(1) }
        if swipeH > swipeThreshold      { swipeH = 0; navigate(-1) }
        else if swipeH < -swipeThreshold { swipeH = 0; navigate(1) }
    }

    private func drillTo(day: Date) {
        direction = -1
        withAnimation(.easeInOut(duration: 0.18)) {
            selected = day; anchor = day; mode = .day
        }
    }

    private func drillTo(year: Int, month: Int) {
        direction = -1
        withAnimation(.easeInOut(duration: 0.18)) {
            anchor = Cal.date(year, month, 1); mode = .case_month
        }
    }

    // ── Content ──────────────────────────────────────────────────────────────
    @ViewBuilder private var content: some View {
        switch mode {
        case .case_month: monthView
        case .week:       weekView
        case .year:       yearView
        case .day:        dayView
        }
    }

    // ── Month ────────────────────────────────────────────────────────────────
    private var monthView: some View {
        let (y, m, _) = Cal.ymd(anchor)
        let rows = Cal.monthGrid(y, m)
        let todayKey = DateKey.today

        return GeometryReader { geo in
            let cw = geo.size.width / 7
            let ch = (geo.size.height - 24) / CGFloat(rows.count)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { n in
                        Text(n).font(F.r(9)).foregroundStyle(P.textS)
                            .frame(width: cw, height: 24)
                    }
                }
                ForEach(rows.indices, id: \.self) { ri in
                    HStack(spacing: 0) {
                        ForEach(rows[ri].indices, id: \.self) { ci in
                            let day = rows[ri][ci]
                            if day == 0 {
                                Color.clear.frame(width: cw, height: ch)
                            } else {
                                let d = Cal.date(y, m, day)
                                let p = store.pct(for: d)
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6).fill(pctColor(p))
                                    if DateKey.string(d) == todayKey {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(P.primary, lineWidth: 2)
                                    }
                                    VStack(spacing: 1) {
                                        Text("\(day)").font(F.b(11))
                                        if let p { Text("\(p)%").font(F.r(8)) }
                                    }
                                    .foregroundStyle(pctTextColor(p))
                                }
                                .padding(2)
                                .frame(width: cw, height: ch)
                                .contentShape(Rectangle())
                                .onTapGesture { drillTo(day: d) }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Week ─────────────────────────────────────────────────────────────────
    private var weekView: some View {
        let mon = Cal.mondayOf(anchor)
        let days = (0..<7).map { Cal.adding(mon, days: $0) }
        let todayKey = DateKey.today

        return GeometryReader { geo in
            let barW = geo.size.width / 7
            let baseY = geo.size.height - 40
            let fullH = baseY - 10

            ZStack(alignment: .topLeading) {
                ForEach(days.indices, id: \.self) { i in
                    let d = days[i]
                    let raw = store.pct(for: d)
                    let p = raw ?? 0
                    let barH = max(4, CGFloat(p) / 100 * fullH)
                    let barTop = baseY - barH
                    let x = CGFloat(i) * barW + barW * 0.1
                    let w = barW * 0.8

                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(P.calNone)
                            .frame(width: w, height: fullH)
                            .offset(x: x, y: 10)
                        Rectangle().fill(pctColor(raw))
                            .frame(width: w, height: barH)
                            .offset(x: x, y: barTop)

                        if let raw {
                            Text("\(raw)%")
                                .font(F.b(9))
                                .foregroundStyle(barTop > 22 ? P.textB : .white)
                                .frame(width: w)
                                .offset(x: x, y: barTop > 22 ? barTop - 16 : barTop + 4)
                        }

                        VStack(spacing: 2) {
                            Text(Cal.fmt(d, "EEE"))
                                .font(DateKey.string(d) == todayKey ? F.b(10) : F.r(10))
                                .foregroundStyle(DateKey.string(d) == todayKey ? P.primary : P.textS)
                            Text("\(Cal.ymd(d).d)").font(F.r(9)).foregroundStyle(P.textS)
                        }
                        .frame(width: w)
                        .offset(x: x, y: baseY + 4)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { drillTo(day: d) }
                }
            }
        }
    }

    // ── Year ─────────────────────────────────────────────────────────────────
    private var yearView: some View {
        let y = Cal.ymd(anchor).y
        return GeometryReader { geo in
            let mw = geo.size.width / 4
            let mh = geo.size.height / 3

            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { col in
                            let month = row * 4 + col + 1
                            monthMini(y: y, month: month, w: mw, h: mh)
                        }
                    }
                }
            }
        }
    }

    private func monthMini(y: Int, month: Int, w: CGFloat, h: CGFloat) -> some View {
        let cell = min(w / 7, (h - 22) / 6) - 1
        let lead = Cal.weekdayIndex(Cal.date(y, month, 1))
        let count = Cal.daysInMonth(y, month)

        return VStack(spacing: 2) {
            Text(Cal.fmt(Cal.date(y, month, 1), "MMM"))
                .font(F.b(11)).foregroundStyle(P.textH)
                .frame(height: 18)
            ZStack(alignment: .topLeading) {
                ForEach(1...count, id: \.self) { d in
                    let wd = (lead + d - 1) % 7
                    let wr = (lead + d - 1) / 7
                    Rectangle()
                        .fill(pctColor(store.pct(for: Cal.date(y, month, d))))
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(wd) * (cell + 1), y: CGFloat(wr) * (cell + 1))
                }
            }
            .frame(width: 7 * (cell + 1), height: 6 * (cell + 1), alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .onTapGesture { drillTo(year: y, month: month) }
    }

    // ── Day ──────────────────────────────────────────────────────────────────
    private var dayView: some View {
        let d = selected
        let amounts = store.amounts(for: d)
        let p = store.pct(for: d)

        return GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                if let amounts {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        ZStack {
                            Circle()
                                .stroke(P.ringBg, style: StrokeStyle(lineWidth: 18))
                                .frame(width: 122, height: 122)
                            if let p, p > 0 {
                                Circle()
                                    .trim(from: 0, to: min(1, Double(p) / 100))
                                    .stroke(p >= 100 ? P.mint : P.primary,
                                            style: StrokeStyle(lineWidth: 18))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 122, height: 122)
                            }
                            VStack(spacing: 2) {
                                Text("\(p ?? 0)%").font(F.b(22)).foregroundStyle(P.textH)
                                Text("of goal").font(F.r(10)).foregroundStyle(P.textS)
                            }
                        }

                        Spacer(minLength: 12)

                        Text("\(fmt(amounts.ml, store.unit)) drank")
                            .font(F.r(12)).foregroundStyle(P.textB)
                        Text("Goal: \(goalFmt(amounts.goal, store.unit))")
                            .font(F.r(11)).foregroundStyle(P.textS)
                            .padding(.top, 6)

                        Spacer(minLength: 12)

                        ZStack {
                            Rectangle().fill(pctColor(p))
                            Text((p ?? 0) >= 100 ? "Goal met! 🏆"
                                                 : "\(100 - (p ?? 0))% away from goal")
                                .font(F.b(10)).foregroundStyle(pctTextColor(p))
                        }
                        .frame(width: min(240, geo.size.width - 60), height: 22)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("No data for this day")
                        .font(F.r(14)).foregroundStyle(P.textS)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Text("✎  Edit day")
                    .font(F.r(10)).foregroundStyle(P.primary)
                    .contentShape(Rectangle())
                    .onTapGesture { editingDay = d }
                    .padding(.top, 4)
            }
        }
    }
}

struct DayBox: Identifiable {
    let day: Date
    var id: String { DateKey.string(day) }
}

// ── Edit a whole day's total ─────────────────────────────────────────────────
struct EditDaySheet: View {
    @EnvironmentObject var store: HydrateStore
    @Environment(\.dismiss) private var dismiss
    let day: Date

    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Cal.fmt(day, "EEEE, MMMM")) \(Cal.ymd(day).d) \(Cal.ymd(day).y)")
                .font(F.b(13)).foregroundStyle(P.textH)
                .padding(.top, 20).padding(.bottom, 4)
            Text("Total intake for the day:")
                .font(F.r(11)).foregroundStyle(P.textS)

            HStack(spacing: 8) {
                FlatField(placeholder: "", text: $text, width: 90, font: F.r(14), onSubmit: save)
                Text(store.unit).font(F.r(13)).foregroundStyle(P.textB)
            }
            .padding(.top, 10)

            HStack(spacing: 12) {
                PillButton(title: "Save", bg: P.primary, fg: .white,
                           font: F.b(12), vPad: 8, hPad: 16, fill: false, action: save)
                PillButton(title: "Cancel", bg: P.border, fg: P.textS,
                           font: F.b(12), vPad: 8, hPad: 16, fill: false) { dismiss() }
            }
            .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .frame(width: 320, height: 230)
        .background(P.bg)
        .onAppear { text = editString(store.amounts(for: day)?.ml ?? 0, store.unit) }
        .alert("Invalid", isPresented: $invalid) {
            Button("OK") {}
        } message: {
            Text("Please enter a valid amount.")
        }
    }

    private func save() {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)) else { invalid = true; return }
        let ml = toML(v, store.unit)
        guard ml >= 0 else { invalid = true; return }
        store.setTotal(for: day, ml: ml)
        dismiss()
    }
}
