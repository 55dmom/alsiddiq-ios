import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Colours for this button only (light / dark follow the system).
enum AdkTheme {
    static let accent = dyn(light: 0x0F766E, dark: 0x2DD4BF)
    static let accent2 = dyn(light: 0x0E7490, dark: 0x0EA5E9)
    static let bg = dyn(light: 0xF3F5F7, dark: 0x0B0E12)
    static let card = dyn(light: 0xFFFFFF, dark: 0x161A20)
    static let line = dyn(light: 0xE4E8EE, dark: 0x262C35)
    static let soft = dyn(light: 0xE2EEED, dark: 0x1A3F3F)
    static let gold = dyn(light: 0xB7791F, dark: 0xF2C14E)
    static let good = dyn(light: 0x15803D, dark: 0x4ADE80)
    static let warn = dyn(light: 0xC2410C, dark: 0xFB923C)
    static var gradient: LinearGradient {
        LinearGradient(colors: [dyn(light: 0x0F766E, dark: 0x0C645D), dyn(light: 0x0E7490, dark: 0x0B627A)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
struct AdkCard<Content: View>: View {
    var padding: CGFloat = 16
    let content: Content
    init(padding: CGFloat = 16, @ViewBuilder _ content: () -> Content) { self.padding = padding; self.content = content() }
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(AdkTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdkTheme.line, lineWidth: 0.6))
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
    }
}

/// Gradient header card: title, subtitle, a glyph and an optional progress ring.
struct AdkHero<Trailing: View>: View {
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
                AdkTheme.gradient
                Circle().fill(Color.white.opacity(0.10)).frame(width: 180, height: 180).offset(x: -120, y: -60)
                Circle().fill(Color.white.opacity(0.07)).frame(width: 120, height: 120).offset(x: 140, y: 50)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AdkTheme.accent.opacity(0.30), radius: 16, x: 0, y: 8)
    }
}

/// Animated progress ring.
struct AdkRing<Center: View>: View {
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
            Circle().stroke(onGradient ? Color.white.opacity(0.25) : AdkTheme.soft, lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(onGradient ? AnyShapeStyle(Color.white) : AnyShapeStyle(AdkTheme.gradient),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            center
        }
        .frame(width: size, height: size)
    }
}

/// A pill that animates between selected / not selected.
struct AdkChip: View {
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
                    Capsule().fill(selected ? AnyShapeStyle(AdkTheme.gradient) : AnyShapeStyle(AdkTheme.card))
                )
                .overlay(Capsule().stroke(selected ? Color.clear : AdkTheme.line, lineWidth: 0.8))
        }
        .buttonStyle(AdkPress())
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
    }
}

/// Search field.
struct AdkSearch: View {
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AdkTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdkTheme.line, lineWidth: 0.6))
    }
}

/// Friendly empty state.
struct AdkEmpty: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(AdkTheme.soft).frame(width: 84, height: 84)
                Image(systemName: icon).font(.system(size: 34, weight: .semibold)).foregroundColor(AdkTheme.accent)
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
struct AdkPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

enum AdkHaptics {
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
enum AdkNum {
    static func s(_ n: Int) -> String { String(n) }
}

extension View {
    /// Arabic, right-to-left.
    func adkRTL() -> some View {
        environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
    }
}
