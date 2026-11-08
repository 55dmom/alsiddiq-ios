import SwiftUI
import UIKit

/// One colour set for the whole app. The status colours (green/red/orange…) stay the same in every theme.
struct Palette: Equatable {
    var navy: UInt32, navyDark: UInt32, navyMid: UInt32, navySoft: UInt32
    var maroon: UInt32, maroonSoft: UInt32
    var gold: UInt32, goldSoft: UInt32, goldInk: UInt32
    var bg: UInt32, card: UInt32, ink: UInt32, muted: UInt32, line: UInt32
    var dark = false
    /// Accent handed to his tool buttons (nil = the tool keeps its own colours).
    var toolAccent: UInt32? = nil
    var toolSoft: UInt32? = nil
    var toolBg: UInt32? = nil
}

struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let sub: String
    let palette: Palette
}

/// An occasion theme, read at runtime from his bundled files (tafaul_occasion_themes.json, occasion_themes_national.json).
/// FORCED while its dates are active (overriding the user's choice); the more specific occasion wins.
struct OccasionTheme: Identifiable, Equatable {
    struct Card: Equatable { let title: String; let body: String; let icon: String; let color: String }
    let id: String
    let theme: AppTheme
    let card: Card?
    let force: Bool
}

enum Occasions {
    /// When each occasion applies (his file has no dates). Umm al-Qura calendar for Hijri; fixed Gregorian days for national days.
    /// Higher priority wins on overlapping days.
    private static let rules: [String: (priority: Int, test: (_ hm: Int, _ hd: Int, _ gm: Int, _ gd: Int) -> Bool)] = [
        "sep26": (100, { _, _, gm, gd in gm == 9 && gd == 26 }),
        "may22": (100, { _, _, gm, gd in gm == 5 && gd == 22 }),
        "arafah": (50, { hm, hd, _, _ in hm == 12 && hd == 9 }),
        "eid-adha": (50, { hm, hd, _, _ in hm == 12 && (10...13).contains(hd) }),
        "eid-fitr": (50, { hm, hd, _, _ in hm == 10 && (1...3).contains(hd) }),
        "hijri-new-year": (50, { hm, hd, _, _ in hm == 1 && hd == 1 }),
        "ashura": (50, { hm, hd, _, _ in hm == 1 && (9...10).contains(hd) }),
        "dhul-hijjah": (20, { hm, hd, _, _ in hm == 12 && (1...8).contains(hd) }),
        "ramadan": (20, { hm, _, _, _ in hm == 9 }),
        "white-days": (10, { _, hd, _, _ in (13...15).contains(hd) }),
    ]

    static let files = ["tafaul_occasion_themes", "occasion_themes_national"]
    static let all: [OccasionTheme] = load()

    private static func load() -> [OccasionTheme] {
        var out: [OccasionTheme] = []
        for f in files {
            guard let url = Bundle.main.url(forResource: f, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            for (key, v) in root {
                guard let o = v as? [String: Any], let t = o["theme"] as? [String: Any] else { continue }
                let pal = Palettes.named(t["palette"] as? String ?? "", accent: t["accent"] as? String ?? "gold")
                var card: OccasionTheme.Card?
                if let home = o["home"] as? [String: Any], let c = (home["cards"] as? [[String: Any]])?.first {
                    let title = (c["title"] as? [String: Any])?["ar"] as? String ?? ""
                    let body = (c["body"] as? [String: Any])?["ar"] as? String ?? ""
                    card = .init(title: title, body: body, icon: c["icon"] as? String ?? "sparkles", color: c["color"] as? String ?? "gold")
                }
                let id = t["id"] as? String ?? key
                out.append(OccasionTheme(id: id, theme: AppTheme(id: "occasion-" + id, name: card?.title ?? id, sub: "", palette: pal),
                                         card: card, force: t["force"] as? Bool ?? true))
            }
        }
        return out
    }

    static func active(on date: Date) -> OccasionTheme? {
        let h = Calendar(identifier: .islamicUmmAlQura).dateComponents([.month, .day], from: date)
        let g = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        let hm = h.month ?? 0, hd = h.day ?? 0, gm = g.month ?? 0, gd = g.day ?? 0
        return all.filter { $0.force && (rules[$0.id]?.test(hm, hd, gm, gd) ?? false) }
            .max { (rules[$0.id]?.priority ?? 0) < (rules[$1.id]?.priority ?? 0) }
    }
}

/// The palettes his occasion file names, and its accent names.
enum Palettes {
    static func accent(_ name: String) -> (UInt32, UInt32, UInt32) { // accent, soft, ink
        switch name {
        case "orange": return (0xE07B24, 0xFCEBDB, 0x8A4510)
        case "sky": return (0x38A3D1, 0xE1F2FA, 0x145C7A)
        case "indigo": return (0x5B5BD6, 0xE8E8FA, 0x2F2F8A)
        case "sand": return (0xC8A877, 0xF6EEDF, 0x6E5428)
        case "teal": return (0x2A9D8F, 0xDDF2EF, 0x13574F)
        case "emerald": return (0x15803D, 0xDFF3E6, 0x0D4A24)
        default: return (0xC9A24A, 0xFBF3E0, 0x7A5C14) // gold
        }
    }
    static func color(_ name: String) -> Color { Color(hex: accent(name).0) }

    static func named(_ name: String, accent a: String) -> Palette {
        var p: Palette
        switch name {
        case "midnight": p = Palette(navy: 0x1B1F4B, navyDark: 0x0E1130, navyMid: 0x2B3170, navySoft: 0x1E2347,
                                     maroon: 0x6A3F8F, maroonSoft: 0x2C2244, gold: 0, goldSoft: 0, goldInk: 0,
                                     bg: 0x0D1026, card: 0x171B3A, ink: 0xEEF0FA, muted: 0xA3A8C8, line: 0x2A2F55, dark: true)
        case "emerald": p = Themes.emerald.palette
        case "desert": p = Palette(navy: 0x7A4B1E, navyDark: 0x55330F, navyMid: 0x9A6330, navySoft: 0xF6E8D6,
                                   maroon: 0x8C3B2A, maroonSoft: 0xF6E5DF, gold: 0, goldSoft: 0, goldInk: 0,
                                   bg: 0xFCF5EA, card: 0xFFFDF8, ink: 0x33220F, muted: 0x806A52, line: 0xEFE0CA, toolAccent: 0x9A6330, toolSoft: 0xF6E8D6)
        case "steel": p = Palette(navy: 0x37474F, navyDark: 0x263238, navyMid: 0x4F6470, navySoft: 0xE6ECEF,
                                  maroon: 0x6B2A2C, maroonSoft: 0xF6E9E9, gold: 0, goldSoft: 0, goldInk: 0,
                                  bg: 0xF4F7F8, card: 0xFFFFFF, ink: 0x1F2A30, muted: 0x67767E, line: 0xDDE5E8, toolAccent: 0x37474F, toolSoft: 0xE6ECEF)
        case "ocean": p = Palette(navy: 0x0B4F6C, navyDark: 0x073449, navyMid: 0x12708F, navySoft: 0xE1F0F5,
                                  maroon: 0x6B2A2C, maroonSoft: 0xF6E9E9, gold: 0, goldSoft: 0, goldInk: 0,
                                  bg: 0xF3F9FB, card: 0xFFFFFF, ink: 0x0F2A35, muted: 0x5E7883, line: 0xD7E8EE, toolAccent: 0x0B4F6C, toolSoft: 0xE1F0F5)
        case "violet": p = Palette(navy: 0x4C1D95, navyDark: 0x321166, navyMid: 0x6D28D9, navySoft: 0xEFE8FB,
                                   maroon: 0x6B2A2C, maroonSoft: 0xF6E9E9, gold: 0, goldSoft: 0, goldInk: 0,
                                   bg: 0xF8F6FD, card: 0xFFFFFF, ink: 0x22173A, muted: 0x6E6585, line: 0xE6E0F3, toolAccent: 0x5B21B6, toolSoft: 0xEFE8FB)
        case "graphite": p = Palette(navy: 0x3F3F46, navyDark: 0x27272A, navyMid: 0x52525B, navySoft: 0xECECEE,
                                     maroon: 0x6B2A2C, maroonSoft: 0xF6E9E9, gold: 0, goldSoft: 0, goldInk: 0,
                                     bg: 0xF6F6F7, card: 0xFFFFFF, ink: 0x1C1C1F, muted: 0x6B6B73, line: 0xE2E2E5, toolAccent: 0x3F3F46, toolSoft: 0xECECEE)
        case "yemen": p = Palette(navy: 0xB5121B, navyDark: 0x7A0A11, navyMid: 0xCE1126, navySoft: 0xFBE9EA,
                                  maroon: 0x1A1A1A, maroonSoft: 0xEDEDED, gold: 0, goldSoft: 0, goldInk: 0,
                                  bg: 0xFAFAFA, card: 0xFFFFFF, ink: 0x111111, muted: 0x666666, line: 0xE5E5E5, toolAccent: 0xB5121B, toolSoft: 0xFBE9EA)
        default: p = Themes.original.palette
        }
        let (ac, soft, ink) = accent(a)
        p.gold = ac
        p.goldSoft = p.dark ? 0x3A3220 : soft
        p.goldInk = p.dark ? 0xE8C877 : ink
        return p
    }
}

/// The occasion's greeting card (top of home and of the password screen).
struct OccasionCard: View {
    @ObservedObject var store = ThemeStore.shared
    var onDark = true
    var body: some View {
        if let c = store.occasion?.card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: c.icon).font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Palettes.color(c.color))
                    .frame(width: 44, height: 44)
                    .background(SwiftUI.Circle().fill(onDark ? Color.white.opacity(0.14) : Brand.goldSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title).font(T.titleMedium).foregroundColor(onDark ? .white : Brand.ink)
                    Text(c.body).font(T.bodySmall).foregroundColor(onDark ? .white.opacity(0.85) : Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(onDark ? Color.white.opacity(0.10) : Brand.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palettes.color(c.color).opacity(0.7), lineWidth: 1))
            .accessibilityIdentifier("occasionCard")
        }
    }
}

enum Themes {
    static let original = AppTheme(id: "original", name: "الأصلي", sub: "كحلي وعنابي وذهبي", palette: Palette(
        navy: 0x282564, navyDark: 0x1B1947, navyMid: 0x3A3486, navySoft: 0xE9E8F5,
        maroon: 0x6B2A2C, maroonSoft: 0xF6E9E9, gold: 0xC9A24A, goldSoft: 0xFBF3E0, goldInk: 0x7A5C14,
        bg: 0xF7F7FB, card: 0xFFFFFF, ink: 0x1E1D2F, muted: 0x6E6D80, line: 0xE6E5EF))
    static let emerald = AppTheme(id: "emerald", name: "زمردي", sub: "أخضر زمردي مع الذهبي", palette: Palette(
        navy: 0x0F5132, navyDark: 0x093421, navyMid: 0x17704A, navySoft: 0xE2F1E9,
        maroon: 0x7A4A12, maroonSoft: 0xF5ECDD, gold: 0xC9A24A, goldSoft: 0xFBF3E0, goldInk: 0x7A5C14,
        bg: 0xF4F8F5, card: 0xFFFFFF, ink: 0x14261C, muted: 0x627268, line: 0xDDE9E1,
        toolAccent: 0x0F6B43, toolSoft: 0xE2F1E9))
    static let night = AppTheme(id: "night", name: "ليلي", sub: "داكن مريح للعين", palette: Palette(
        navy: 0x232E52, navyDark: 0x121A33, navyMid: 0x34437A, navySoft: 0x222B45,
        maroon: 0x9A4447, maroonSoft: 0x3A2426, gold: 0xD9B45A, goldSoft: 0x3A3220, goldInk: 0xE8C877,
        bg: 0x0E1220, card: 0x182036, ink: 0xECEDF5, muted: 0x9CA1B9, line: 0x2A3350, dark: true))
    static let sand = AppTheme(id: "sand", name: "رملي", sub: "كريمي ورملي هادئ", palette: Palette(
        navy: 0x5E4426, navyDark: 0x412E18, navyMid: 0x7D5D37, navySoft: 0xF1E8D8,
        maroon: 0x8C3B2A, maroonSoft: 0xF6E5DF, gold: 0xB8893A, goldSoft: 0xF8EEDB, goldInk: 0x6E4F12,
        bg: 0xFBF6EC, card: 0xFFFDF8, ink: 0x2E2418, muted: 0x7A6C5A, line: 0xEBE2D0,
        toolAccent: 0x7D5D37, toolSoft: 0xF1E8D8, toolBg: 0xFBF6EC))
    static let royal = AppTheme(id: "royal", name: "أزرق ملكي", sub: "أزرق ملكي مع الذهبي", palette: Palette(
        navy: 0x1E3A8A, navyDark: 0x142663, navyMid: 0x2B50B5, navySoft: 0xE5EBFA,
        maroon: 0x6B2A2C, maroonSoft: 0xF6E9E9, gold: 0xC9A24A, goldSoft: 0xFBF3E0, goldInk: 0x7A5C14,
        bg: 0xF5F7FC, card: 0xFFFFFF, ink: 0x18213A, muted: 0x66708A, line: 0xE1E6F2,
        toolAccent: 0x1E40AF, toolSoft: 0xE5EBFA))
    static let all = [original, emerald, night, sand, royal]
}

/// The active theme: an active occasion wins, else the user's choice (stored with @AppStorage "appTheme").
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    static let key = "appTheme"
    nonisolated(unsafe) static var palette: Palette = Themes.original.palette

    @Published private(set) var active: AppTheme = Themes.original
    @Published private(set) var occasion: OccasionTheme?
    private var midnight: Timer?

    init() {
        refresh()
        // re-check at each new day (an occasion may start or end)
        midnight = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in Task { @MainActor in ThemeStore.shared.refresh() } }
    }

    var chosenId: String { UserDefaults.standard.string(forKey: Self.key) ?? Themes.original.id }

    func choose(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.key)
        refresh()
    }

    /// CI screenshots only (Debug builds): "-debugDate yyyy-MM-dd" pretends today is that day.
    nonisolated static var today: Date {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "debugDate") {
            let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: s) { return d.addingTimeInterval(12 * 3600) }
        }
        #endif
        return Date()
    }

    func refresh(now: Date = ThemeStore.today) {
        let forced = Occasions.active(on: now)
        let chosen = Themes.all.first { $0.id == chosenId } ?? Themes.original
        let t = forced?.theme ?? chosen
        occasion = forced
        Self.palette = t.palette
        if t != active { active = t }
        AppFont.applyBars()
    }

    /// His tool packages read only these colour keys (their texts and logic are untouched).
    private static func publishToolPalette(_ p: Palette) {
        let d = UserDefaults.standard
        for (k, v) in [("accent", p.toolAccent), ("soft", p.toolSoft), ("bg", p.toolBg)] {
            if let v { d.set(Int(v), forKey: "alsiddiq.toolPalette." + k) } else { d.removeObject(forKey: "alsiddiq.toolPalette." + k) }
        }
    }
}

/// «الثيمات»: open to everyone, no password.
struct ThemesScreen: View {
    @ObservedObject var store = ThemeStore.shared
    var onClose: (() -> Void)? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let o = store.occasion {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill").foregroundColor(Brand.gold)
                        Text("ثيم المناسبة «\(o.card?.title ?? o.id)» مفعّل الآن، ويرجع اختيارك بعد انتهاء المناسبة")
                            .font(T.bodyMedium).foregroundColor(Brand.ink)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.goldSoft))
                }
                ForEach(Themes.all) { t in
                    let selected = store.chosenId == t.id
                    Button { store.choose(t.id) } label: { ThemeRow(theme: t, selected: selected, locked: store.occasion != nil) }
                        .buttonStyle(.plain)
                        .disabled(store.occasion != nil)
                        .accessibilityIdentifier("theme_" + t.id)
                }
            }
            .padding(18)
        }
        .background(Brand.bg.ignoresSafeArea())
        .appNavTitle("الثيمات")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemeRow: View {
    let theme: AppTheme
    let selected: Bool
    let locked: Bool
    var body: some View {
        let p = theme.palette
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: p.navy), Color(hex: p.maroon)], startPoint: .topLeading, endPoint: .bottomTrailing))
                SwiftUI.Circle().fill(Color(hex: p.gold)).frame(width: 18, height: 18).offset(x: 12, y: 12)
                SwiftUI.Circle().fill(Color(hex: p.bg)).overlay(SwiftUI.Circle().stroke(Color(hex: p.line), lineWidth: 1)).frame(width: 14, height: 14).offset(x: -12, y: -12)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name).font(T.titleMedium).foregroundColor(Brand.ink)
                Text(theme.sub).font(T.bodySmall).foregroundColor(Brand.muted)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : (locked ? "lock" : "circle"))
                .font(.system(size: 22)).foregroundColor(selected ? Brand.gold : Brand.muted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? Brand.gold : Brand.line, lineWidth: selected ? 2 : 1))
        .opacity(locked && !selected ? 0.55 : 1)
    }
}

/// The occasion's greeting popup: once per day per occasion, when the app opens; closes with «شكراً».
struct OccasionGreeting: View {
    let occasion: OccasionTheme
    let onClose: () -> Void
    @State private var shine = false

    private static func dayKey(_ o: OccasionTheme) -> (String, String) {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return ("occasionGreetingShown." + o.id, f.string(from: ThemeStore.today))
    }
    static func shouldShow(_ o: OccasionTheme) -> Bool {
        let (k, d) = dayKey(o); return UserDefaults.standard.string(forKey: k) != d
    }
    static func markShown(_ o: OccasionTheme) {
        let (k, d) = dayKey(o); UserDefaults.standard.set(d, forKey: k)
    }

    var body: some View {
        let c = occasion.card!
        let tint = Palettes.color(c.color)
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                ZStack {
                    SwiftUI.Circle().fill(tint.opacity(shine ? 0.45 : 0.22)).frame(width: 120, height: 120).blur(radius: 18)
                    SwiftUI.Circle().fill(Color.white.opacity(0.14)).frame(width: 84, height: 84)
                    Image(systemName: c.icon).font(.system(size: 40, weight: .semibold)).foregroundColor(tint)
                }
                .frame(height: 120)
                Text(c.title).font(T.headlineSmall).foregroundColor(.white).multilineTextAlignment(.center)
                Text(c.body).font(T.bodyLarge).foregroundColor(.white.opacity(0.88)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onClose) {
                    Text("شكراً").font(T.titleMedium).foregroundColor(Brand.navyDark)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Capsule().fill(tint))
                }
                .padding(.top, 6)
                .accessibilityIdentifier("greetingThanks")
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.navy, Brand.navyDark], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(tint.opacity(0.8), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 28)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { shine = true } }
        .accessibilityIdentifier("occasionGreeting")
    }
}
