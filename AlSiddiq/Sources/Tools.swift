import SwiftUI
import Mushaf
import Hifz
import Khatma
import PrayerTimes
import Adhkar
import Duas
import Tasbeeh
import AsmaAllah

/// «الأدوات»: side tools anyone can open, no password. More items (المصحف، الأذكار…) are added here later.
enum ToolItem: String, CaseIterable, Identifiable, Hashable {
    case mushaf, hifz, khatma, prayer, adhkar, duas, tasbeeh, asma
    case themes   // «الثيمات», not a tool: listed apart at the end
    static var tools: [ToolItem] { allCases.filter { $0 != .themes } }
    var id: String { rawValue }
    var title: String {
        switch self { case .themes: return "الثيمات"; case .mushaf: return "المصحف"; case .hifz: return "وضع الحفظ"; case .khatma: return "الختمة"; case .prayer: return "مواقيت الصلاة"; case .adhkar: return "الأذكار"; case .duas: return "الأدعية"; case .tasbeeh: return "المسبحة"; case .asma: return "أسماء الله الحسنى" }
    }
    var sub: String {
        switch self {
        case .themes: return "ألوان التطبيق"
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
        switch self { case .themes: return "paintpalette"; case .mushaf: return "book.closed"; case .hifz: return "brain.head.profile"; case .khatma: return "checkmark.seal"; case .prayer: return "clock"; case .adhkar: return "sun.and.horizon"; case .duas: return "hands.sparkles"; case .tasbeeh: return "hand.tap"; case .asma: return "sparkles" }
    }
    @ViewBuilder var screen: some View {
        switch self {
        case .themes: ThemesScreen()
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
    func show(_ item: ToolItem? = nil) {
        path = item.map { [$0] } ?? []
        open = true
    }
}

/// The small «الأدوات» button (opening screen, home headers, settings).
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

/// The side menu itself, presented as a sheet; each tool opens inside it.
struct ToolsSheet: View {
    @EnvironmentObject var tools: ToolsHost
    @ObservedObject var theme = ThemeStore.shared
    var body: some View {
        NavigationStack(path: $tools.path) {
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
                }
                .padding(18)
            }
            .background(Brand.bg.ignoresSafeArea())
            .navigationDestination(for: ToolItem.self) { $0.screen }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { tools.open = false }.foregroundColor(Brand.maroon)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .id(theme.active.id)
        .tint(Brand.navy)
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(theme.active.palette.dark ? .dark : .light)
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
