import SwiftUI
import CoreText

/// Amiri Quran (SIL OFL 1.1), bundled for Qur'anic text.
enum HfFont {
    static let quranName = "Amiri Quran"
    private static var registered = false
    static func register() {
        if registered { return }
        registered = true
        if let u = Bundle.module.url(forResource: "AmiriQuran-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
        }
    }
    static func quran(_ size: CGFloat) -> Font {
        register()
        return .custom(quranName, size: size)
    }
}
