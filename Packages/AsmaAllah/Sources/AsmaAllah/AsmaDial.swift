import SwiftUI

/// The dial + the progress bar, redrawn every frame from the model's needle clock (ported from the تفاؤل design).
struct AsmaDialCanvas: View {
    @ObservedObject var m: AsmaModel
    let R: CGFloat
    let cy: CGFloat
    let progTop: CGFloat
    private let rtl = true

    var body: some View {
        let labelSize = R * 0.050
        let idx = m.idx
        let done = m.done
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                CineParticles.draw(&ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate, count: 22)
                draw(&ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate, idx: idx, done: done)
            } symbols: {
                ForEach(0..<AsmaModel.count, id: \.self) { k in
                    Text(verbatim: AsmaData.names[k].plain).font(.custom("Tajawal-Bold", size: labelSize)).foregroundColor(.white).fixedSize().tag(k)
                }
            }
        }
    }

    private func dir(_ k: Double) -> CGPoint { let th = k * 2 * .pi / Double(AsmaModel.count); return CGPoint(x: sin(th), y: -cos(th)) }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, idx: Int, done: Bool) {
        let N = AsmaModel.count
        let a = m.pos(t)
        let cx = size.width / 2
        let c = CGPoint(x: cx, y: cy)
        func pt(_ d: CGPoint, _ r: CGFloat) -> CGPoint { CGPoint(x: c.x + d.x * r, y: c.y + d.y * r) }
        func circle(_ r: CGFloat, _ at: CGPoint? = nil) -> Path { let p = at ?? c; return Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)) }

        // progress bar (10 segments) — fills with the needle
        do {
            let x0: CGFloat = rtl ? 26 : 100, x1 = rtl ? size.width - 100 : size.width - 26
            let segs = 10, gap: CGFloat = 2.5
            let sw = (x1 - x0 - gap * CGFloat(segs - 1)) / CGFloat(segs)
            let f = done ? 1.0 : min(max((a + 1) / Double(N), 0), 1)
            let filled = f * Double(segs)
            let y = progTop + 1, h: CGFloat = 10
            for s in 0..<segs {
                let xs = rtl ? x1 - CGFloat(s) * (sw + gap) - sw : x0 + CGFloat(s) * (sw + gap)
                ctx.fill(Path(roundedRect: CGRect(x: xs, y: y, width: sw, height: h), cornerRadius: h / 2), with: .color(.white.opacity(0.10)))
                let part = CGFloat(min(max(filled - Double(s), 0), 1))
                if part > 0 {
                    let w = sw * part
                    let xa = rtl ? xs + sw - w : xs
                    ctx.fill(Path(roundedRect: CGRect(x: xa, y: y, width: w, height: h), cornerRadius: h / 2),
                             with: .linearGradient(Gradient(colors: [AsmaUI.red, AsmaUI.redHi]), startPoint: CGPoint(x: xa, y: y), endPoint: CGPoint(x: xa + sw, y: y)))
                }
            }
        }
        // glow + shadow ring
        ctx.fill(circle(R * 1.35), with: .radialGradient(Gradient(colors: [.white.opacity(0.05), .clear]), center: c, startRadius: 0, endRadius: R * 1.35))
        ctx.fill(circle(R * 1.07), with: .radialGradient(Gradient(stops: [.init(color: .black.opacity(0.55), location: 0.80), .init(color: .clear, location: 1)]), center: c, startRadius: 0, endRadius: R * 1.07))
        // disk + bevel rim
        ctx.fill(circle(R), with: .radialGradient(Gradient(colors: [Color(red: 0.118, green: 0.118, blue: 0.133).opacity(0.80), Color(red: 0.086, green: 0.086, blue: 0.102).opacity(0.84), Color(red: 0.067, green: 0.067, blue: 0.078).opacity(0.90)]), center: c, startRadius: 0, endRadius: R))
        ctx.stroke(circle(R - 1), with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.04), .white.opacity(0.10)]), startPoint: CGPoint(x: cx - R, y: cy - R), endPoint: CGPoint(x: cx + R, y: cy + R)), lineWidth: 1.6)
        ctx.stroke(circle(R * 0.975), with: .color(.black.opacity(0.35)), lineWidth: 1)
        ctx.stroke(circle(R * 0.685), with: .color(.white.opacity(0.06)), lineWidth: 0.8)
        ctx.stroke(circle(R * 0.865), with: .color(.white.opacity(0.045)), lineWidth: 0.8)
        // ticks
        let lit = done ? Double(N) : a + 0.5
        for k in 0..<N {
            let d = dir(Double(k))
            let major = k % 11 == 0
            let r2 = R * 0.952, r1 = major ? R * 0.872 : R * 0.905
            let on = Double(k) < lit
            let near = CGFloat(min(max(1 - abs(Double(k) - a), 0), 1))
            var p = Path(); p.move(to: pt(d, r1)); p.addLine(to: pt(d, r2))
            let col: Color = on ? .white.opacity(major ? 0.95 : 0.78) : .white.opacity(major ? 0.42 : 0.22)
            ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: (major ? 1.7 : 1.05) + near * 0.6, lineCap: .round))
        }
        // names around: right half reads outward, left half inward; outer ends aligned
        let rOut = R * 0.845
        let maxW = R * 0.33
        for k in 0..<N {
            guard let sym = ctx.resolveSymbol(id: k) else { continue }
            let deg = Double(k) * 360 / Double(N)
            let hl = done ? 0 : CGFloat(min(max(1 - abs(Double(k) - a), 0), 1))
            let passed = done || k <= idx
            let base: CGFloat = passed ? 0.80 : 0.40
            let alpha = base + hl * (1 - base)
            let w0 = sym.size.width, h0 = sym.size.height
            let fit = w0 > maxW ? maxW / w0 : 1
            let sc = fit * (1 + 0.30 * hl)
            let right = deg < 180
            var g = ctx
            g.translateBy(x: cx, y: cy)
            g.rotate(by: .degrees(right ? deg - 90 : deg + 90))
            let ax: CGFloat = right ? rOut : -rOut
            g.translateBy(x: ax, y: 0)
            g.scaleBy(x: sc, y: sc)
            if hl > 0.02 {
                let bx: CGFloat = right ? -w0 - 3 / sc : -3 / sc
                g.fill(Path(roundedRect: CGRect(x: bx, y: -h0 / 2 - 1 / sc, width: w0 + 6 / sc, height: h0 + 2 / sc), cornerRadius: 4 / sc), with: .color(.black.opacity(0.55 * hl)))
            }
            g.opacity = alpha
            g.draw(sym, at: .zero, anchor: right ? .trailing : .leading)
        }
        // centre hub + pulse
        let hubR = R * 0.245
        let pulse = (t - m.pulseAt) / 0.7
        if pulse >= 0 && pulse <= 1 {
            let pf = CGFloat(pulse)
            ctx.stroke(circle(hubR * (1 + 0.42 * pf)), with: .color(AsmaUI.red.opacity(0.35 * (1 - pulse))), lineWidth: 2.4 * (1 - pf) + 0.6)
        }
        ctx.fill(circle(hubR), with: .radialGradient(Gradient(colors: [Color(red: 0.09, green: 0.09, blue: 0.10), Color(red: 0.047, green: 0.047, blue: 0.055)]), center: c, startRadius: 0, endRadius: hubR))
        ctx.stroke(circle(hubR), with: .color(.white.opacity(0.13)), lineWidth: 1)
        let hs: CGFloat = (pulse >= 0 && pulse <= 1) ? 1 + 0.06 * CGFloat(sin(Double.pi * pulse)) : 1
        var hc = ctx
        hc.translateBy(x: c.x, y: c.y); hc.scaleBy(x: hs, y: hs)
        hc.draw(Text(verbatim: "\(done ? N : idx + 1)").font(.custom("Tajawal-Bold", size: hubR * 0.62)).foregroundColor(.white.opacity(0.92)), at: CGPoint(x: 0, y: hubR * 0.04))
        // completion: a red light runs once around the rim
        let dp = (t - m.doneAt) / 1.6
        if done && dp >= 0 && dp <= 1 {
            let pc = pt(dir(dp * Double(N)), R * 0.93)
            ctx.fill(circle(R * 0.12, pc), with: .radialGradient(Gradient(colors: [AsmaUI.redHi.opacity(0.8 * (1 - dp)), .clear]), center: pc, startRadius: 0, endRadius: R * 0.12))
        }
        // needle
        let d = dir(a)
        let p0 = pt(d, hubR + 4), p1 = pt(d, R * 0.60)
        var nl = Path(); nl.move(to: p0); nl.addLine(to: p1)
        ctx.stroke(nl, with: .color(AsmaUI.red.opacity(0.22)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        ctx.stroke(nl, with: .color(AsmaUI.red), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
        ctx.fill(circle(5, p0), with: .color(Color(red: 0.055, green: 0.055, blue: 0.063)))
        ctx.stroke(circle(5, p0), with: .color(AsmaUI.red), lineWidth: 2)
        let pm = pt(d, R * 0.912)
        ctx.fill(circle(7.5, pm), with: .color(AsmaUI.red.opacity(0.25)))
        ctx.stroke(circle(5.5, pm), with: .color(AsmaUI.redHi), lineWidth: 1.8)
    }
}
