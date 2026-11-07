import SwiftUI
import CoreText

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// Palette taken from the centre's logo (same values as the Android app).
enum Brand {
    static let navy = Color(hex: 0x282564)
    static let navyDark = Color(hex: 0x1B1947)
    static let navyMid = Color(hex: 0x3A3486)
    static let navySoft = Color(hex: 0xE9E8F5)
    static let maroon = Color(hex: 0x6B2A2C)
    static let maroonSoft = Color(hex: 0xF6E9E9)
    static let gold = Color(hex: 0xC9A24A)
    static let goldSoft = Color(hex: 0xFBF3E0)
    static let goldInk = Color(hex: 0x7A5C14)
    static let green = Color(hex: 0x2E7D5B)
    static let greenSoft = Color(hex: 0xE5F3EC)
    static let teal = Color(hex: 0x3C8D7A)
    static let orange = Color(hex: 0xD9822B)
    static let red = Color(hex: 0xC0392B)
    static let bg = Color(hex: 0xF7F7FB)
    static let card = Color.white
    static let ink = Color(hex: 0x1E1D2F)
    static let muted = Color(hex: 0x6E6D80)
    static let line = Color(hex: 0xE6E5EF)
    static let silver = Color(hex: 0xA7A9B4)
    static let bronze = Color(hex: 0xB0773F)
}

/// IBM Plex Sans Arabic, the same face as the Android app, registered from the bundle at launch.
enum AppFont {
    private static var names: [Font.Weight: String] = [:]

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
        // Navigation and tab bars use the same face.
        if let ps = names[.semibold], let ui = UIFont(name: ps, size: 17) {
            UINavigationBar.appearance().titleTextAttributes = [.font: ui, .foregroundColor: UIColor(Brand.ink)]
        }
        if let ps = names[.medium], let ui = UIFont(name: ps, size: 11) {
            UITabBarItem.appearance().setTitleTextAttributes([.font: ui], for: .normal)
        }
    }

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
