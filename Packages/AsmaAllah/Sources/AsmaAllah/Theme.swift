import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Colours for this button only (light / dark follow the system).
enum AsmTheme {
    static let accent = dyn(light: 0x7A5A12, dark: 0xE0B64F)
    static let bg = dyn(light: 0xF4F6F5, dark: 0x0E1110)
    static let card = dyn(light: 0xFFFFFF, dark: 0x1A1F1D)
    static let line = dyn(light: 0xE3E8E6, dark: 0x2A312E)
    static let soft = dyn(light: 0xE8F3EF, dark: 0x16302A)

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

/// A rounded card.
struct AsmCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(AsmTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AsmTheme.line, lineWidth: 0.5))
    }
}

enum AsmHaptics {
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

extension View {
    /// Arabic, right-to-left.
    func asmRTL() -> some View {
        environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
    }
}
