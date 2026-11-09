import SwiftUI

/// Bead flow state, in seconds (Date().timeIntervalSinceReferenceDate). Each tap glides one bead spacing (0.32 s ease-out from
/// wherever the beads are, so fast taps stay continuous); entering glides 9 beads in.
final class TsbFlow {
    var from: Double = -9, to: Double = 0, t0: Double = 0, dur: Double = 1.25
    var taps: [Double] = []
    var done: Double = -100
    static func now() -> Double { Date().timeIntervalSinceReferenceDate }
    func phase(_ t: Double) -> Double {
        let k = min(max((t - t0) / dur, 0), 1)
        let e = dur > 0.5 ? 1 - pow(1 - k, 3) : 1 - pow(1 - k, 2)
        return from + (to - from) * e
    }
    func tap(_ t: Double = TsbFlow.now()) {
        from = phase(t); to = to.rounded() + 1; t0 = t; dur = 0.32
        taps.append(t); if taps.count > 6 { taps.removeFirst(taps.count - 6) }
    }
    func enter(_ t: Double = TsbFlow.now()) { from = to - 9; t0 = t; dur = 1.25 }
    func lastTap() -> Double { taps.last ?? -100 }
}

/// The whole moving scene in one Canvas: light particles, a thin breathing string, ~29 glass beads, glow, ripples and "+1".
struct TsbSceneCanvas: View {
    let flow: TsbFlow
    let markerBase: Double
    let target: Int
    let cyRatio: CGFloat

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                CineParticles.draw(&ctx, size: size, t: t)
                TsbSceneCanvas.draw(ctx: &ctx, size: size, t: t, flow: flow, markerBase: markerBase, target: max(target, 1), cyRatio: cyRatio)
            }
        }
        .allowsHitTesting(false)
    }

    static func waveY(_ x: CGFloat, w: CGFloat, cy: CGFloat, t: Double) -> CGFloat {
        let a0 = w * 0.052
        let breathe = 1 + 0.10 * sin(2 * .pi * t / 5.6)
        let q = Double((x - w / 2) / w)
        let main = cos(2 * .pi * q) * Double(a0) * breathe
        let drift = sin(2 * .pi * (q * 1.4) - 2 * .pi * t / 7.5) * Double(a0) * 0.16
        return cy + CGFloat(main + drift)
    }

    static func draw(ctx: inout GraphicsContext, size: CGSize, t: Double, flow: TsbFlow, markerBase: Double, target: Int, cyRatio: CGFloat) {
        let w = size.width, h = size.height
        let cy = h * cyRatio
        let n = 180
        let x0 = -w * 0.06, x1 = w * 1.06
        var pts: [CGPoint] = []; pts.reserveCapacity(n + 1)
        var len: [CGFloat] = [0]; len.reserveCapacity(n + 1)
        for i in 0...n {
            let x = x0 + (x1 - x0) * CGFloat(i) / CGFloat(n)
            let p = CGPoint(x: x, y: waveY(x, w: w, cy: cy, t: t))
            if let l = pts.last { len.append(len.last! + hypot(p.x - l.x, p.y - l.y)) }
            pts.append(p)
        }
        func at(_ s: CGFloat) -> CGPoint {
            if s <= 0 { return pts[0] }
            if s >= len[n] { return pts[n] }
            var lo = 0, hi = n
            while hi - lo > 1 { let m = (lo + hi) / 2; if len[m] < s { lo = m } else { hi = m } }
            let k = (s - len[lo]) / max(len[hi] - len[lo], 0.0001)
            return CGPoint(x: pts[lo].x + (pts[hi].x - pts[lo].x) * k, y: pts[lo].y + (pts[hi].y - pts[lo].y) * k)
        }
        var sc: CGFloat = 0
        do { var lo = 0, hi = n; while hi - lo > 1 { let m = (lo + hi) / 2; if pts[m].x < w / 2 { lo = m } else { hi = m } }; sc = len[lo] }

        var line = Path(); line.addLines(pts)
        ctx.stroke(line, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.42), location: 0.16),
                                                                  .init(color: .white.opacity(0.55), location: 0.5), .init(color: .white.opacity(0.42), location: 0.84),
                                                                  .init(color: .clear, location: 1)]),
                                            startPoint: CGPoint(x: 0, y: cy), endPoint: CGPoint(x: w, y: cy)), lineWidth: 1.1)

        let ph = flow.phase(t)
        let fl = floor(ph), fr = ph - fl
        let gap = w / 22.5
        let rb = w / 54
        let since = t - flow.lastTap()
        let tapGlow = since < 0.6 ? pow(1 - since / 0.6, 2) : 0
        let centre = at(sc)
        let doneK = t - flow.done
        let gr = rb * (5.2 + 1.6 * tapGlow)
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x - gr, y: centre.y - gr * 0.9, width: gr * 2, height: gr * 1.8)),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.80, green: 0.96, blue: 1).opacity(0.26 + 0.30 * tapGlow), .clear]),
                                       center: centre, startRadius: 0, endRadius: gr))
        if doneK >= 0 && doneK < 1.4 {
            let k = doneK / 1.4
            let rr = rb * (3 + 22 * k)
            ctx.fill(Path(ellipseIn: CGRect(x: centre.x - rr, y: centre.y - rr, width: rr * 2, height: rr * 2)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.35 * (1 - k)), .clear]), center: centre, startRadius: 0, endRadius: rr))
        }
        // beads, back to front by distance from the centre so the centre bead sits on top
        let step = target == 100 ? 10 : 11
        var order: [Int] = Array(-14...14)
        order.sort { abs(Double($0) + fr) > abs(Double($1) + fr) }
        for k in order {
            let u = Double(k) + fr
            let s = sc + CGFloat(u) * gap
            let p = at(s)
            let ex = min(max(p.x / (w * 0.16), 0), 1), ex2 = min(max((w - p.x) / (w * 0.16), 0), 1)
            let edge = smooth(ex) * smooth(ex2)
            if edge <= 0.01 { continue }
            let d = abs(u)
            let emph = 1 + 0.32 * exp(-(d * d) / 2.2)
            let j = Int(fl) - k
            let rel = Double(j) - markerBase
            let jj = (rel.truncatingRemainder(dividingBy: Double(target)) + Double(target)).truncatingRemainder(dividingBy: Double(target))
            let kind: Int = jj == 0 ? 2 : ((Int(rel) % step + step) % step == 0 ? 1 : 0)
            let r = rb * CGFloat(emph) * (kind == 2 ? 1.18 : 1) * (0.88 + 0.12 * edge)
            bead(&ctx, p, r, kind: kind, alpha: edge, lit: d < 0.5 ? tapGlow : 0)
        }
        let cr = rb * 1.32
        ctx.stroke(Path(ellipseIn: CGRect(x: centre.x - cr * 1.75, y: centre.y - cr * 1.75, width: cr * 3.5, height: cr * 3.5)), with: .color(.white.opacity(0.20)), lineWidth: 0.8)
        for tt in flow.taps {
            let k = (t - tt) / 0.5
            guard k >= 0, k < 1 else { continue }
            let e = 1 - pow(1 - k, 2)
            let rr = cr * (1.75 + 2.6 * CGFloat(e))
            ctx.stroke(Path(ellipseIn: CGRect(x: centre.x - rr, y: centre.y - rr, width: rr * 2, height: rr * 2)),
                       with: .color(Color(red: 0.86, green: 0.98, blue: 1).opacity(0.75 * (1 - k) * (1 - k))), lineWidth: 1.6 * CGFloat(1 - k) + 0.4)
        }
        for tt in flow.taps {
            let k = (t - tt) / 0.75
            guard k >= 0, k < 1 else { continue }
            let pop = k < 0.18 ? 0.7 + 0.3 * (k / 0.18) * 1.15 : 1.0
            let txt = Text(verbatim: "\u{200E}+1").font(.system(size: 15 * pop, weight: .bold, design: .rounded)).foregroundColor(Color(red: 1, green: 0.80, blue: 0.62))
            var c2 = ctx
            c2.opacity = (1 - k) * (1 - k * 0.2)
            c2.draw(txt, at: CGPoint(x: centre.x + cr * 2.3, y: centre.y - cr * 2.6 - CGFloat(26 * (1 - pow(1 - k, 2)))))
        }
    }

    static func smooth(_ x: CGFloat) -> CGFloat { x * x * (3 - 2 * x) }

    static func bead(_ ctx: inout GraphicsContext, _ p: CGPoint, _ r: CGFloat, kind: Int, alpha: CGFloat, lit: Double) {
        var c = ctx
        c.opacity = Double(alpha)
        c.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.1, y: p.y - r * 0.5, width: r * 2.2, height: r * 2.0)),
               with: .radialGradient(Gradient(colors: [.black.opacity(0.32), .clear]), center: CGPoint(x: p.x, y: p.y + r * 0.45), startRadius: 0, endRadius: r * 1.2))
        let cols: [Color]
        switch kind {
        case 1: cols = [Color(red: 1, green: 0.86, blue: 0.80), Color(red: 0.95, green: 0.42, blue: 0.28), Color(red: 0.62, green: 0.13, blue: 0.08), Color(red: 0.25, green: 0.04, blue: 0.03)]
        case 2: cols = [Color(red: 1, green: 0.95, blue: 0.82), Color(red: 1, green: 0.74, blue: 0.38), Color(red: 0.78, green: 0.42, blue: 0.12), Color(red: 0.32, green: 0.15, blue: 0.04)]
        default: cols = [Color(red: 0.97, green: 1, blue: 1), Color(red: 0.76, green: 0.91, blue: 0.93), Color(red: 0.40, green: 0.58, blue: 0.64), Color(red: 0.13, green: 0.22, blue: 0.27)]
        }
        let hl = CGPoint(x: p.x - r * 0.36, y: p.y - r * 0.40)
        let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        c.fill(disc, with: .radialGradient(Gradient(stops: [.init(color: cols[0], location: 0), .init(color: cols[1], location: 0.28),
                                                            .init(color: cols[2], location: 0.72), .init(color: cols[3], location: 1)]),
                                           center: hl, startRadius: 0, endRadius: r * 1.75))
        let bl = CGPoint(x: p.x + r * 0.30, y: p.y + r * 0.42)
        c.fill(disc, with: .radialGradient(Gradient(colors: [(kind == 0 ? Color(red: 0.75, green: 1, blue: 1) : Color(red: 1, green: 0.85, blue: 0.6)).opacity(0.42), .clear]),
                                           center: bl, startRadius: 0, endRadius: r * 0.75))
        if lit > 0 { c.fill(disc, with: .color(.white.opacity(0.35 * lit))) }
        c.stroke(disc, with: .color(.white.opacity(0.28)), lineWidth: max(0.5, r * 0.07))
        c.fill(Path(ellipseIn: CGRect(x: hl.x - r * 0.20, y: hl.y - r * 0.13, width: r * 0.40, height: r * 0.26)), with: .color(.white.opacity(0.92)))
    }
}

/// Small dark counter: count + thin progress arc, "/33" under it; pops on each tap, a warm ring at the end of a round.
struct TsbCounter: View {
    let flow: TsbFlow
    let count: Int
    let target: Int
    static let boxW: CGFloat = 120, boxH: CGFloat = 116
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let k = (t - flow.lastTap()) / 0.24
            let pop = (k >= 0 && k < 1) ? 1 + 0.10 * sin(.pi * k) : 1
            let dk = t - flow.done
            VStack(spacing: 8) {
                ZStack {
                    if dk >= 0 && dk < 0.9 {
                        Circle().stroke(Color(red: 1, green: 0.86, blue: 0.62).opacity(0.6 * (1 - dk / 0.9)), lineWidth: 1.5)
                            .scaleEffect(1 + 0.55 * (dk / 0.9))
                    }
                    Circle().fill(Color.black.opacity(0.46))
                    Circle().stroke(Color.white.opacity(0.13), lineWidth: 2.5).padding(3)
                    Circle().trim(from: 0, to: min(Double(count) / Double(max(target, 1)), 1))
                        .stroke(Color(red: 0.80, green: 0.95, blue: 0.98), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(3)
                    Text(verbatim: Cine.num(count))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(width: 74, height: 86, alignment: .center)
                        .scaleEffect(pop)
                }
                .frame(width: 86, height: 86)
                Text(verbatim: "\u{200E}/" + Cine.num(target))
                    .font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundColor(.white.opacity(0.72))
                    .frame(width: TsbCounter.boxW, alignment: .center)
            }
            .frame(width: TsbCounter.boxW, alignment: .top)
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}
