import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum DuaFilter: Int, CaseIterable, Identifiable {
    case all, quran, sunnah, fav
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .all: return "الكل"
        case .quran: return "من القرآن"
        case .sunnah: return "من السنة"
        case .fav: return "المفضلة"
        }
    }
}

enum DuaText {
    /// Removes harakat / Qur'anic marks and unifies letter forms, for search.
    static func norm(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            let v = u.value
            if (0x064B...0x065F).contains(v) || v == 0x0670 || (0x06D6...0x06ED).contains(v) || v == 0x0640 { continue }
            switch v {
            case 0x0622, 0x0623, 0x0625, 0x0671: out.append("ا")
            case 0x0629: out.append("ه")
            case 0x0649: out.append("ي")
            case 0x0624: out.append("و")
            case 0x0626: out.append("ي")
            default: out.unicodeScalars.append(u)
            }
        }
        return out
    }
}

final class DuaModel: ObservableObject {
    private let d = UserDefaults.standard
    private let k = "alsalmi.duas."
    @Published var filter: DuaFilter = .all
    @Published var query: String = ""
    @Published var openSource: Set<String> = []
    @Published var toast: String = ""
    @Published var favs: Set<String> { didSet { d.set(Array(favs), forKey: k + "favs") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: k + "font") } }
    private let index: [String: String]

    init() {
        favs = Set(d.stringArray(forKey: k + "favs") ?? [])
        let fs = d.double(forKey: k + "font")
        fontSize = fs > 0 ? fs : 21
        var ix: [String: String] = [:]
        for x in DuasData.all { ix[x.id] = DuaText.norm(x.text + " " + x.cat + " " + x.ref) }
        index = ix
    }

    var cats: [String] {
        var seen: [String] = []
        for x in DuasData.all where !x.quran && !seen.contains(x.cat) { seen.append(x.cat) }
        return seen
    }

    var items: [DuaItem] {
        var xs = DuasData.all
        switch filter {
        case .all: break
        case .quran: xs = xs.filter { $0.quran }
        case .sunnah: xs = xs.filter { !$0.quran }
        case .fav: xs = xs.filter { favs.contains($0.id) }
        }
        let q = DuaText.norm(query.trimmingCharacters(in: .whitespaces))
        if !q.isEmpty { xs = xs.filter { (index[$0.id] ?? "").contains(q) } }
        return xs
    }

    func count(_ f: DuaFilter) -> Int {
        switch f {
        case .all: return DuasData.all.count
        case .quran: return DuasData.all.filter { $0.quran }.count
        case .sunnah: return DuasData.all.filter { !$0.quran }.count
        case .fav: return favs.count
        }
    }

    func toggleFav(_ id: String) {
        if favs.contains(id) { favs.remove(id) } else { favs.insert(id) }
    }
    func toggleSource(_ id: String) {
        if openSource.contains(id) { openSource.remove(id) } else { openSource.insert(id) }
    }
    func show(_ t: String) {
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.toast == t { self?.toast = "" }
        }
    }
}

/// «الأدعية» — the button's single entry view.
public struct DuasView: View {
    @StateObject private var m = DuaModel()

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    DuaHero(title: "الأدعية", subtitle: String(m.count(.quran)) + " دعاء من القرآن، و" + String(m.count(.sunnah)) + " من السنة الصحيحة\nكل دعاء معه مصدره") {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.18)).frame(width: 70, height: 70)
                            Image(systemName: "book.closed.fill").font(.system(size: 30, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                    DuaSearch(placeholder: "ابحث في الأدعية: كرب، سفر، مطر…", text: $m.query)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DuaFilter.allCases) { f in
                                DuaChip(title: f.title + "  " + String(m.count(f)), selected: m.filter == f) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { m.filter = f }
                                }
                            }
                        }
                        .padding(.vertical, 4).padding(.horizontal, 2)
                    }
                    let xs = m.items
                    if xs.isEmpty {
                        if m.filter == .fav && m.query.isEmpty {
                            DuaEmpty(icon: "heart", title: "ما عندك مفضلة للحين", message: "اضغط على القلب تحت أي دعاء يعجبك، ويصير هنا قريب منك.")
                        } else {
                            DuaEmpty(icon: "magnifyingglass", title: "ما لقينا شي", message: "جرّب كلمة ثانية، مثل: الهم، السفر، المطر، المسجد.")
                        }
                    } else {
                        ForEach(xs) { x in card(x).transition(.opacity.combined(with: .scale(scale: 0.97))) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .animation(.spring(response: 0.4, dampingFraction: 0.86), value: m.filter)
                .animation(.easeOut(duration: 0.2), value: m.query)
            }
            if !m.toast.isEmpty {
                Text(verbatim: m.toast)
                    .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Capsule().fill(DuaTheme.gradient))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: m.toast)
        .background(DuaTheme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "الأدعية"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { m.fontSize = max(16, m.fontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                    .accessibilityLabel(Text(verbatim: "تصغير الخط"))
                Button { m.fontSize = min(36, m.fontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                    .accessibilityLabel(Text(verbatim: "تكبير الخط"))
            }
        }
        .tint(DuaTheme.accent)
        .duaRTL()
    }

    private func card(_ x: DuaItem) -> some View {
        let fav = m.favs.contains(x.id)
        let open = m.openSource.contains(x.id)
        return DuaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(verbatim: x.quran ? "قرآن" : x.cat)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(x.quran ? DuaTheme.gold.opacity(0.15) : DuaTheme.soft))
                        .foregroundColor(x.quran ? DuaTheme.gold : DuaTheme.accent)
                    if x.count > 1 {
                        Text(verbatim: String(x.count) + " مرات").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { m.toggleFav(x.id) }
                        DuaHaptics.tap()
                    } label: {
                        Image(systemName: fav ? "heart.fill" : "heart")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(fav ? Color.pink : .secondary)
                            .scaleEffect(fav ? 1.15 : 1)
                    }
                    .buttonStyle(DuaPress())
                    .accessibilityLabel(Text(verbatim: "المفضلة"))
                }
                Text(verbatim: x.text)
                    .font(x.quran ? DuaFont.quran(m.fontSize + 1) : .system(size: m.fontSize))
                    .lineSpacing(x.quran ? 12 : 8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if !x.reward.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(DuaTheme.gold).frame(width: 3)
                        Text(verbatim: x.reward).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 10) {
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { m.toggleSource(x.id) } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: open ? "chevron.up" : "book.closed")
                            Text(verbatim: x.ref).lineLimit(1)
                        }
                        .font(.footnote.weight(.medium)).foregroundColor(DuaTheme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(DuaTheme.soft))
                    }
                    .buttonStyle(DuaPress())
                    Spacer()
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = x.text + "\n— " + x.ref
                        #endif
                        DuaHaptics.success()
                        m.show("تم النسخ")
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38).background(Circle().fill(DuaTheme.soft)).foregroundColor(DuaTheme.accent)
                    }
                    .buttonStyle(DuaPress())
                    .accessibilityLabel(Text(verbatim: "نسخ"))
                    ShareLink(item: x.text + "\n— " + x.ref) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38).background(Circle().fill(DuaTheme.soft)).foregroundColor(DuaTheme.accent)
                    }
                    .buttonStyle(DuaPress())
                    .accessibilityLabel(Text(verbatim: "مشاركة"))
                }
                if open {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "المصدر: " + x.source)
                        Text(verbatim: "الحكم: " + x.grade)
                        if !x.note.isEmpty { Text(verbatim: "ملاحظة: " + x.note) }
                    }
                    .font(.footnote).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DuaTheme.soft))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}
