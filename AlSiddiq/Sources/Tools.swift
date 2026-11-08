import SwiftUI
import Mushaf
import Hifz
import Khatma
import PrayerTimes
import Adhkar
import Duas
import Tasbeeh
import AsmaAllah
import Contact

/// «الأدوات»: side tools anyone can open, no password. More items (المصحف، الأذكار…) are added here later.
enum ToolItem: String, CaseIterable, Identifiable, Hashable {
    case mushaf, hifz, khatma, prayer, adhkar, duas, tasbeeh, asma
    case themes   // «الثيمات», not a tool: listed apart at the end
    case about, developer   // «عن المركز» and «تواصل مع المطوّر»: public pages, listed apart
    static var tools: [ToolItem] { allCases.filter { ![.themes, .about, .developer].contains($0) } }
    var id: String { rawValue }
    var title: String {
        switch self { case .about: return "عن المركز"; case .developer: return "تواصل مع المطوّر"; case .themes: return "الثيمات"; case .mushaf: return "المصحف"; case .hifz: return "وضع الحفظ"; case .khatma: return "الختمة"; case .prayer: return "مواقيت الصلاة"; case .adhkar: return "الأذكار"; case .duas: return "الأدعية"; case .tasbeeh: return "المسبحة"; case .asma: return "أسماء الله الحسنى" }
    }
    var sub: String {
        switch self {
        case .themes: return "ألوان التطبيق"
        case .about: return "نبذة المركز وصوره وعنوانه وأرقام التواصل"
        case .developer: return "قناة تفاؤل في تيليجرام"
        case .mushaf: return "المصحف كاملاً برسم المصحف العثماني"
        case .hifz: return "احفظ وراجع بإخفاء الآيات"
        case .khatma: return "خطة ختمة ومتابعة الورد اليومي"
        case .prayer: return "أوقات الصلاة والإقامة والتاريخ الهجري"
        case .adhkar: return "أذكار الصباح والمساء وغيرها"
        case .duas: return "أدعية من القرآن والسنة"
        case .tasbeeh: return "عداد التسبيح مع الأذكار"
        case .asma: return "الأسماء الحسنى ومعانيها"
        }
    }
    var icon: String {
        switch self { case .about: return "info.circle"; case .developer: return "paperplane"; case .themes: return "paintpalette"; case .mushaf: return "book.closed"; case .hifz: return "brain.head.profile"; case .khatma: return "checkmark.seal"; case .prayer: return "clock"; case .adhkar: return "sun.and.horizon"; case .duas: return "hands.sparkles"; case .tasbeeh: return "hand.tap"; case .asma: return "sparkles" }
    }
    @ViewBuilder var screen: some View {
        switch self {
        case .themes: ThemesScreen()
        case .about: AboutCenterScreen()
        case .developer: ContactDeveloperView()   // his package, unchanged and fixed (not editable)
        case .mushaf: MushafView()
        case .hifz: HifzView()
        case .khatma: KhatmaView()
        case .prayer: PrayerTimesView()
        case .adhkar: AdhkarView()
        case .duas: DuasView()
        case .tasbeeh: TasbeehView()
        case .asma: AsmaAllahView()
        }
    }
}

@MainActor
final class ToolsHost: ObservableObject {
    @Published var open = false
    @Published var path: [ToolItem] = []
    /// The «الأدوات» tab's own stack (the bottom bar hides while a tool is open on it).
    @Published var tabPath: [ToolItem] = []
    func show(_ item: ToolItem? = nil) {
        path = item.map { [$0] } ?? []
        open = true
    }
}

/// The small «الأدوات» button on the opening (password) screen.
struct ToolsButton: View {
    var light = true
    @EnvironmentObject var tools: ToolsHost
    var body: some View {
        Button { tools.show() } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 14, weight: .semibold))
                Text("الأدوات").font(T.labelLarge)
            }
            .foregroundColor(light ? .white : Brand.navy)
            .padding(.horizontal, 12).frame(height: 36)
            .background(Capsule().fill(light ? Color.white.opacity(0.14) : Brand.navySoft))
            .overlay(Capsule().stroke(Brand.gold.opacity(0.7), lineWidth: 1))
        }
        .accessibilityIdentifier("toolsButton")
    }
}

/// The small «عن المركز» button beside «الأدوات» on the opening and password screens (no password needed).
struct AboutButtonSmall: View {
    var light = true
    @EnvironmentObject var tools: ToolsHost
    var body: some View {
        Button { tools.show(.about) } label: {
            HStack(spacing: 5) {
                Image(systemName: "info.circle.fill").font(.system(size: 14, weight: .semibold))
                Text("عن المركز").font(T.labelLarge)
            }
            .foregroundColor(light ? .white : Brand.navy)
            .padding(.horizontal, 12).frame(height: 36)
            .background(Capsule().fill(light ? Color.white.opacity(0.14) : Brand.navySoft))
            .overlay(Capsule().stroke(Brand.gold.opacity(0.7), lineWidth: 1))
        }
        .accessibilityIdentifier("aboutButton")
    }
}

/// The side menu itself, presented as a sheet; each tool opens inside it.
struct ToolsSheet: View {
    @EnvironmentObject var tools: ToolsHost
    @EnvironmentObject var model: AppModel
    @ObservedObject var theme = ThemeStore.shared
    /// Dialogs opened inside the sheet (e.g. the admin's «عن المركز» buttons) show above it, not behind it.
    @StateObject private var dialogs = DialogHost()
    var body: some View {
        ZStack {
            stack
            if let d = dialogs.content {
                Color.black.opacity(0.32).ignoresSafeArea().onTapGesture { dialogs.dismiss() }.transition(.opacity)
                d.transition(.scale(scale: 0.94).combined(with: .opacity)).zIndex(2)
            }
            if let t = model.toast {
                VStack { Spacer(); ToastView(text: t).padding(.bottom, 28) }
                    .transition(.move(edge: .bottom).combined(with: .opacity)).zIndex(3).allowsHitTesting(false)
            }
        }
        .environmentObject(dialogs)
        .id(theme.active.id)
        .tint(Brand.navy)
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(theme.active.palette.dark ? .dark : .light)
    }

    private var stack: some View {
        NavigationStack(path: $tools.path) {
            ToolsMenuList()
            .navigationDestination(for: ToolItem.self) { $0.screen }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { tools.open = false }.foregroundColor(Brand.maroon)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The «الأدوات» menu itself: the 8 tools in order, then «الثيمات», «عن المركز» and «تواصل مع المطوّر».
/// Shown in the sheet (opening screen, settings) and as the «الأدوات» tab.
struct ToolsMenuList: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image("Logo").resizable().scaledToFit().frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("الأدوات").font(T.titleLarge).foregroundColor(Brand.ink)
                        Text("لكل من يفتح التطبيق، بدون كلمة سر").font(T.bodySmall).foregroundColor(Brand.muted)
                    }
                }
                .padding(.bottom, 4)
                ForEach(ToolItem.tools) { item in ToolRow(item: item) }
                SectionLabel(text: "المظهر").padding(.top, 6)
                ToolRow(item: .themes)
                SectionLabel(text: "المركز").padding(.top, 6)
                ToolRow(item: .about)
                ToolRow(item: .developer)
            }
            .padding(18)
        }
        .background(Brand.bg.ignoresSafeArea())
    }
}

/// The «الأدوات» tab in the bottom bar: the same menu (no password), each tool opens full screen with a back button.
struct ToolsTabScreen: View {
    @EnvironmentObject var tools: ToolsHost
    var body: some View {
        NavigationStack(path: $tools.tabPath) {
            ToolsMenuList()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ToolItem.self) { $0.screen }
        }
        .tint(Brand.navy)
        .accessibilityIdentifier("toolsTab")
    }
}

private struct SectionLabel: View {
    let text: String
    var body: some View { Text(text).font(T.labelLarge).foregroundColor(Brand.muted) }
}

private struct ToolRow: View {
    let item: ToolItem
    var body: some View {
        NavigationLink(value: item) {
                            HStack(spacing: 14) {
                                Image(systemName: item.icon).font(.system(size: 22, weight: .semibold)).foregroundColor(.white)
                                    .frame(width: 52, height: 52)
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(LinearGradient(colors: [Brand.navy, Brand.maroon], startPoint: .topLeading, endPoint: .bottomTrailing)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(T.titleMedium).foregroundColor(Brand.ink)
                                    Text(item.sub).font(T.bodySmall).foregroundColor(Brand.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.forward").foregroundColor(Brand.gold)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Brand.card))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Brand.gold.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tool_" + item.rawValue)
    }
}
