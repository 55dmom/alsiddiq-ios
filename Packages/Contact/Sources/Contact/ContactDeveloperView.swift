import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Contact info (same as «تواصل معنا» in تفاؤل). Nothing is stored; no accounts, no forms.
enum CtInfo {
    static let title = "تواصل مع المطوّر"
    static let subtitle = "تواصل معنا"
    static let body = "راسلنا على قناة تفاؤل في تيليجرام: اقتراح، سؤال، أو استفسار."
    static let button = "افتح قناة تفاؤل في تيليجرام"
    static let link = "t.me/tafaulapp"
    static let url = URL(string: "https://t.me/tafaulapp")!
}

/// Colours for this button only (light / dark follow the system).
enum CtTheme {
    static let telegram = Color(red: 0.16, green: 0.63, blue: 0.87)
    static let bg = dyn(light: 0xF3F5F7, dark: 0x0B0E12)
    static let card = dyn(light: 0xFFFFFF, dark: 0x161A20)
    static let line = dyn(light: 0xE4E8EE, dark: 0x262C35)
    static let soft = dyn(light: 0xE1F1FA, dark: 0x173244)
    static var gradient: LinearGradient {
        LinearGradient(colors: [dyn(light: 0x2AA1DE, dark: 0x1F86BC), dyn(light: 0x1C7FC0, dark: 0x16628F)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
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

final class CtModel: ObservableObject {
    @Published var copied = false
    @Published var appeared = false
    func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = CtInfo.url.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.copied = false }
        }
    }
}

/// «تواصل مع المطوّر» — the button's single entry view. Put it inside your NavigationStack (or a sheet wrapped in one).
public struct ContactDeveloperView: View {
    @StateObject private var model = CtModel()
    @Environment(\.openURL) private var openURL
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                card
                Text(verbatim: "ما يُحفظ أي شي، وبدون حسابات أو نماذج.")
                    .font(.footnote).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(CtTheme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) { toast }
        .navigationTitle(Text(verbatim: CtInfo.title))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { model.appeared = true } }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.18)).frame(width: 104, height: 104)
                Circle().fill(Color.white).frame(width: 84, height: 84)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(CtTheme.telegram)
                    .offset(x: -2, y: 1)
            }
            .scaleEffect(model.appeared ? 1 : 0.6)
            .opacity(model.appeared ? 1 : 0)
            Text(verbatim: CtInfo.title).font(.title2.weight(.bold)).foregroundColor(.white)
            Text(verbatim: CtInfo.subtitle).font(.subheadline.weight(.medium)).foregroundColor(.white.opacity(0.85))
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                CtTheme.gradient
                Circle().fill(Color.white.opacity(0.10)).frame(width: 200, height: 200).offset(x: -130, y: -70)
                Circle().fill(Color.white.opacity(0.07)).frame(width: 130, height: 130).offset(x: 150, y: 70)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: CtTheme.telegram.opacity(0.30), radius: 16, x: 0, y: 8)
    }

    private var card: some View {
        VStack(spacing: 16) {
            Text(verbatim: CtInfo.body)
                .font(.callout).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { openURL(CtInfo.url) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill")
                    Text(verbatim: CtInfo.button).font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundColor(.white)
                .background(CtTheme.telegram, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(CtPress())
            Text(verbatim: CtInfo.link)
                .font(.footnote.monospaced()).foregroundColor(.secondary)
                .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 10) {
                Button { model.copy() } label: {
                    small(icon: model.copied ? "checkmark" : "doc.on.doc", title: model.copied ? "انتسخ" : "نسخ الرابط")
                }
                .buttonStyle(CtPress())
                ShareLink(item: CtInfo.url) {
                    small(icon: "square.and.arrow.up", title: "مشاركة الرابط")
                }
                .buttonStyle(CtPress())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(CtTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CtTheme.line, lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
        .offset(y: model.appeared ? 0 : 24)
        .opacity(model.appeared ? 1 : 0)
    }

    private func small(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(verbatim: title).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundColor(CtTheme.telegram)
        .background(CtTheme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var toast: some View {
        if model.copied {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text(verbatim: "تم نسخ الرابط")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Gentle shrink while pressed.
struct CtPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
