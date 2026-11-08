import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Colours for this button only (light / dark follow the system).
enum PrTheme {
    static var accent: Color { HostPalette.color("accent") ?? dyn(light: 0x1D4ED8, dark: 0x60A5FA) }
    static let accent2 = dyn(light: 0x0891B2, dark: 0x22D3EE)
    static var bg: Color { HostPalette.color("bg") ?? dyn(light: 0xF3F5F7, dark: 0x0B0E12) }
    static let card = dyn(light: 0xFFFFFF, dark: 0x161A20)
    static let line = dyn(light: 0xE4E8EE, dark: 0x262C35)
    static var soft: Color { HostPalette.color("soft") ?? dyn(light: 0xE3E9FA, dark: 0x24354B) }
    static let gold = dyn(light: 0xB7791F, dark: 0xF2C14E)
    static let good = dyn(light: 0x15803D, dark: 0x4ADE80)
    static let warn = dyn(light: 0xC2410C, dark: 0xFB923C)
    static var gradient: LinearGradient {
        LinearGradient(colors: [dyn(light: 0x1D4ED8, dark: 0x1842B7), dyn(light: 0x0891B2, dark: 0x067B97)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func dyn(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { t in
            let v = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
        #else
        let v = light
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        #endif
    }
}

/// A rounded card with a soft shadow.
struct PrCard<Content: View>: View {
    var padding: CGFloat = 16
    let content: Content
    init(padding: CGFloat = 16, @ViewBuilder _ content: () -> Content) { self.padding = padding; self.content = content() }
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(PrTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PrTheme.line, lineWidth: 0.6))
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
    }
}

/// Gradient header card: title, subtitle, a glyph and an optional progress ring.
struct PrHero<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing
    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.trailing = trailing()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title).font(.title2.weight(.bold)).foregroundColor(.white)
                Text(verbatim: subtitle).font(.subheadline).foregroundColor(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                PrTheme.gradient
                Circle().fill(Color.white.opacity(0.10)).frame(width: 180, height: 180).offset(x: -120, y: -60)
                Circle().fill(Color.white.opacity(0.07)).frame(width: 120, height: 120).offset(x: 140, y: 50)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: PrTheme.accent.opacity(0.30), radius: 16, x: 0, y: 8)
    }
}

/// Animated progress ring.
struct PrRing<Center: View>: View {
    let progress: Double
    var size: CGFloat = 64
    var line: CGFloat = 7
    var onGradient: Bool = true
    let center: Center
    init(progress: Double, size: CGFloat = 64, line: CGFloat = 7, onGradient: Bool = true, @ViewBuilder center: () -> Center) {
        self.progress = progress; self.size = size; self.line = line; self.onGradient = onGradient; self.center = center()
    }
    var body: some View {
        ZStack {
            Circle().stroke(onGradient ? Color.white.opacity(0.25) : PrTheme.soft, lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(onGradient ? AnyShapeStyle(Color.white) : AnyShapeStyle(PrTheme.gradient),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            center
        }
        .frame(width: size, height: size)
    }
}

/// A pill that animates between selected / not selected.
struct PrChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.subheadline.weight(selected ? .bold : .medium))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .foregroundColor(selected ? .white : .primary)
                .background(
                    Capsule().fill(selected ? AnyShapeStyle(PrTheme.gradient) : AnyShapeStyle(PrTheme.card))
                )
                .overlay(Capsule().stroke(selected ? Color.clear : PrTheme.line, lineWidth: 0.8))
        }
        .buttonStyle(PrPress())
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
    }
}

/// Search field.
struct PrSearch: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField(text: $text) { Text(verbatim: placeholder) }
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PrTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PrTheme.line, lineWidth: 0.6))
    }
}

/// Friendly empty state.
struct PrEmpty: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(PrTheme.soft).frame(width: 84, height: 84)
                Image(systemName: icon).font(.system(size: 34, weight: .semibold)).foregroundColor(PrTheme.accent)
            }
            Text(verbatim: title).font(.headline)
            Text(verbatim: message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 36).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

/// Press feedback: a gentle shrink.
struct PrPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

enum PrHaptics {
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

/// Western digits everywhere.
enum PrNum {
    static func s(_ n: Int) -> String { String(n) }
}

extension View {
    /// Arabic, right-to-left.
    func prRTL() -> some View {
        environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
    }
}

/// Small drawn glyphs (no stars): sunrise, sun, moon, dome, book, check, clock, pin, copy.
struct PrIcon: View {
    let kind: String
    var color: Color = .white
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            switch kind {
            case "sunrise":
                Circle().trim(from: 0.5, to: 1).fill(color).frame(width: size * 0.7, height: size * 0.7).offset(y: size * 0.12)
                Capsule().fill(color).frame(width: size * 0.95, height: size * 0.09).offset(y: size * 0.14)
                Capsule().fill(color.opacity(0.7)).frame(width: size * 0.6, height: size * 0.09).offset(y: size * 0.33)
            case "sun":
                Circle().fill(color).frame(width: size * 0.52, height: size * 0.52)
                Circle().stroke(color.opacity(0.35), lineWidth: size * 0.07).frame(width: size * 0.84, height: size * 0.84)
            case "moon":
                Image(systemName: "moon.fill").font(.system(size: size * 0.78, weight: .semibold)).foregroundColor(color)
            case "dome":
                VStack(spacing: 0) {
                    Circle().trim(from: 0.5, to: 1).fill(color).frame(width: size * 0.62, height: size * 0.62).offset(y: size * 0.31)
                    RoundedRectangle(cornerRadius: size * 0.05).fill(color).frame(width: size * 0.8, height: size * 0.36)
                }
                .offset(y: -size * 0.12)
            case "book":
                Image(systemName: "book.fill").font(.system(size: size * 0.72, weight: .semibold)).foregroundColor(color)
            case "check":
                Image(systemName: "checkmark").font(.system(size: size * 0.7, weight: .bold)).foregroundColor(color)
            case "clock":
                Image(systemName: "clock").font(.system(size: size * 0.75, weight: .semibold)).foregroundColor(color)
            case "pin":
                Image(systemName: "mappin.and.ellipse").font(.system(size: size * 0.75, weight: .semibold)).foregroundColor(color)
            default:
                Circle().fill(color).frame(width: size * 0.5, height: size * 0.5)
            }
        }
        .frame(width: size, height: size)
    }
}
