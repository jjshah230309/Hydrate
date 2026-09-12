import SwiftUI

/// The big progress ring — a direct port of the Tk ProgressRing canvas widget.
struct ProgressRingView: View {
    var pct: Double            // 0…100
    var main: String
    var unit: String
    var goal: String
    var size: CGFloat = 190
    var ringW: CGFloat = 18

    private var clamped: Double { max(0, min(100, pct)) }
    private var color: Color { clamped >= 100 ? P.mint : P.primary }

    var body: some View {
        ZStack {
            Circle()
                .stroke(P.ringBg, style: StrokeStyle(lineWidth: ringW, lineCap: .butt))
                .padding(ringW + 8)

            if clamped > 0 {
                Circle()
                    .trim(from: 0, to: clamped / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: ringW, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(ringW + 8)
                    .animation(.easeOut(duration: 0.45), value: clamped)
            }

            Text(main).font(F.b(32)).foregroundStyle(P.textH).offset(y: -16)
            Text(unit).font(F.r(12)).foregroundStyle(P.textB).offset(y: 12)
            Text(goal).font(F.r(10)).foregroundStyle(P.textS).offset(y: 30)
        }
        .frame(width: size, height: size)
    }
}
