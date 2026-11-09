import SwiftUI

/// Islamic geometric pattern (8-point stars from two overlapping squares, the girih/khatam tiling) drawn as thin lines.
/// No lettering, no figures. Used very faintly behind the home screens, and in gold on the opening screen.
struct IslamicPattern: View {
    var color: Color
    var cell: CGFloat = 46
    var lineWidth: CGFloat = 0.8
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(size.width / cell) + 2, rows = Int(size.height / cell) + 2
            var path = Path()
            for r in 0..<rows {
                for c in 0..<cols {
                    let cx = CGFloat(c) * cell, cy = CGFloat(r) * cell
                    let h = cell * 0.36
                    // two squares, one turned 45°: an 8-point star
                    path.addRect(CGRect(x: cx - h, y: cy - h, width: 2 * h, height: 2 * h))
                    let d = h * 1.414
                    path.move(to: CGPoint(x: cx, y: cy - d))
                    path.addLine(to: CGPoint(x: cx + d, y: cy))
                    path.addLine(to: CGPoint(x: cx, y: cy + d))
                    path.addLine(to: CGPoint(x: cx - d, y: cy))
                    path.closeSubpath()
                    // the small square that links four stars
                    let m = cell / 2, q = cell * 0.1
                    path.move(to: CGPoint(x: cx + m, y: cy + m - q))
                    path.addLine(to: CGPoint(x: cx + m + q, y: cy + m))
                    path.addLine(to: CGPoint(x: cx + m, y: cy + m + q))
                    path.addLine(to: CGPoint(x: cx + m - q, y: cy + m))
                    path.closeSubpath()
                }
            }
            ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}

/// The home screens' background: his realistic photo, full-bleed and strongly blurred (ضبابي),
/// under a scrim in the active theme's colours so the text stays readable on every theme.
struct HomeBackdrop: View {
    static let photo: UIImage? = Bundle.main.url(forResource: "home_bg_real", withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Brand.bg
                if let img = Self.photo {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 22, opaque: true)
                        .clipped()
                    LinearGradient(colors: [Brand.bg.opacity(0.40), Brand.bg.opacity(0.54), Brand.bg.opacity(0.68)], startPoint: .top, endPoint: .bottom)
                    Brand.navy.opacity(0.06)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The opening screen's look: deep green to near-black, a gold geometric overlay.
enum Lux {
    static let green = Color(hex: 0x0B3B2C)
    static let greenDeep = Color(hex: 0x072419)
    static let black = Color(hex: 0x040907)
    static let gold = Color(hex: 0xD4AF37)
    static let goldLight = Color(hex: 0xF3D98B)
    static let goldDark = Color(hex: 0x9C7A24)
    static var goldGradient: LinearGradient { LinearGradient(colors: [goldLight, gold, goldDark], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static func title(_ size: CGFloat) -> Font { AppFont.amiri(size) }
}

struct LuxBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Lux.green, Lux.greenDeep, Lux.black], startPoint: .top, endPoint: .bottom)
            IslamicPattern(color: Lux.gold, cell: 52, lineWidth: 0.8).opacity(0.11)
            RadialGradient(colors: [Lux.gold.opacity(0.18), .clear], center: .top, startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// A thin gold ornament line: ── ✦ ──
struct GoldDivider: View {
    var width: CGFloat = 70
    var body: some View {
        HStack(spacing: 8) {
            LinearGradient(colors: [.clear, Lux.gold], startPoint: .leading, endPoint: .trailing).frame(width: width, height: 1)
            Image(systemName: "sparkle").font(.system(size: 10, weight: .semibold)).foregroundColor(Lux.gold)
            LinearGradient(colors: [Lux.gold, .clear], startPoint: .leading, endPoint: .trailing).frame(width: width, height: 1)
        }
    }
}

struct GoldButton: View {
    let title: String
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                if busy { ProgressView().tint(Lux.black) } else {
                    Text(title).font(T.titleMedium).foregroundColor(Lux.black)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Lux.goldGradient))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Lux.goldLight.opacity(0.7), lineWidth: 0.8))
            .shadow(color: Lux.gold.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
    }
}
