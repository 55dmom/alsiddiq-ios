import SwiftUI
import CoreText

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// Palette taken from the centre's logo (same values as the Android app); the theme («الثيمات») swaps the set.
enum Brand {
    private static var p: Palette { ThemeStore.palette }
    static var navy: Color { Color(hex: p.navy) }
    static var navyDark: Color { Color(hex: p.navyDark) }
    static var navyMid: Color { Color(hex: p.navyMid) }
    static var navySoft: Color { Color(hex: p.navySoft) }
    static var maroon: Color { Color(hex: p.maroon) }
    static var maroonSoft: Color { Color(hex: p.maroonSoft) }
    static var gold: Color { Color(hex: p.gold) }
    static var goldSoft: Color { Color(hex: p.goldSoft) }
    static var goldInk: Color { Color(hex: p.goldInk) }
    static let green = Color(hex: 0x2E7D5B)
    static var greenSoft: Color { p.dark ? Color(hex: 0x1D3A2E) : Color(hex: 0xE5F3EC) }
    static let teal = Color(hex: 0x3C8D7A)
    static let orange = Color(hex: 0xD9822B)
    static let red = Color(hex: 0xC0392B)
    static var bg: Color { Color(hex: p.bg) }
    static var card: Color { Color(hex: p.card) }
    static var ink: Color { Color(hex: p.ink) }
    static var muted: Color { Color(hex: p.muted) }
    static var line: Color { Color(hex: p.line) }
    static let silver = Color(hex: 0xA7A9B4)
    static let bronze = Color(hex: 0xB0773F)
}

/// IBM Plex Sans Arabic, the same face as the Android app, registered from the bundle at launch.
enum AppFont {
    private static var names: [Font.Weight: String] = [:]
    private static var amiriName: String?
    /// Amiri (SIL OFL), for the opening screen's centre name.
    static func amiri(_ size: CGFloat) -> Font {
        if let n = amiriName { return .custom(n, fixedSize: size) }
        return .system(size: size, weight: .bold, design: .serif)
    }

    static func register() {
        let files: [(String, Font.Weight)] = [("plex_regular", .regular), ("plex_medium", .medium), ("plex_semibold", .semibold), ("plex_bold", .bold)]
        for (file, weight) in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf"),
                  let provider = CGDataProvider(url: url as CFURL),
                  let font = CGFont(provider) else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterGraphicsFont(font, &error)
            if let ps = font.postScriptName as String? { names[weight] = ps }
        }
        if let url = Bundle.main.url(forResource: "amiri_regular", withExtension: "ttf"),
           let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterGraphicsFont(font, &error)
            amiriName = font.postScriptName as String?
        }
        applyBars()
        if let ps = names[.medium], let ui = UIFont(name: ps, size: 11) {
            UITabBarItem.appearance().setTitleTextAttributes([.font: ui], for: .normal)
        }
    }

    /// Navigation bar titles use the same face, in the active theme's ink.
    /// The navigation bars are left at the system look: only his tool packages use them, and they must look exactly
    /// like his own project. The app's own pages inside the tools stack set their title with `appNavTitle`.
    static func applyBars() {}

    static func f(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let n = names[weight] ?? names[.regular] { return .custom(n, fixedSize: size) }
        return .system(size: size, weight: weight)
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> UIFont {
        if let n = names[weight] ?? names[.regular], let f = UIFont(name: n, size: size) { return f }
        return .systemFont(ofSize: size)
    }
}

/// Type scale mirroring the Android Material typography.
enum T {
    static var displaySmall: Font { AppFont.f(32, .bold) }
    static var headlineMedium: Font { AppFont.f(26, .bold) }
    static var headlineSmall: Font { AppFont.f(22, .bold) }
    static var titleLarge: Font { AppFont.f(20, .semibold) }
    static var titleMedium: Font { AppFont.f(16, .semibold) }
    static var titleSmall: Font { AppFont.f(14, .semibold) }
    static var bodyLarge: Font { AppFont.f(16) }
    static var bodyMedium: Font { AppFont.f(14) }
    static var bodySmall: Font { AppFont.f(12) }
    static var labelLarge: Font { AppFont.f(14, .medium) }
    static var labelMedium: Font { AppFont.f(12, .medium) }
    static var labelSmall: Font { AppFont.f(11, .medium) }
}

func gradeColor(_ g: Grade) -> Color {
    switch g {
    case .excellent: return Brand.green
    case .veryGood: return Brand.teal
    case .good: return Brand.navy
    case .pass: return Brand.orange
    case .weak: return Brand.red
    }
}

func kindColor(_ k: RecordKind) -> Color {
    switch k { case .hifz: return Brand.navy; case .tasmee: return Brand.gold; case .muraja: return Brand.maroon }
}

func kindIcon(_ k: RecordKind) -> String {
    switch k { case .hifz: return "book"; case .tasmee: return "waveform"; case .muraja: return "arrow.counterclockwise" }
}

func attendanceColor(_ s: AttendanceStatus) -> Color {
    switch s { case .present: return Brand.green; case .late: return Brand.orange; case .excused: return Brand.navy; case .absent: return Brand.red }
}


extension View {
    /// A navigation-bar title in the app's own font (the bars themselves keep the system look for his tools).
    func appNavTitle(_ title: String) -> some View {
        navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(AppFont.f(17, .semibold)).foregroundColor(Brand.ink).lineLimit(1)
                }
            }
    }
}
