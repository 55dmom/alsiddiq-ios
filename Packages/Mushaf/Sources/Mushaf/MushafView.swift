import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MsOpen: Identifiable { let id: Int }

enum MsTab: Int, CaseIterable, Identifiable {
    case suras, juz
    var id: Int { rawValue }
    var title: String { self == .suras ? "السور" : "الأجزاء" }
}

final class MsModel: ObservableObject {
    private let d = UserDefaults.standard
    private let k = "alsalmi.mushaf."
    @Published var tab: MsTab = .suras
    @Published var query = ""
    @Published var jump = ""
    @Published var open: MsOpen? = nil
    @Published var page: Int = 1 { didSet { if open != nil { lastPage = page } } }
    @Published var lastPage: Int { didSet { d.set(lastPage, forKey: k + "last") } }
    @Published var bookmark: Int { didSet { d.set(bookmark, forKey: k + "bookmark") } }
    /// The reader's text size as a multiple of the size that fits the whole page on the screen (1 = fit, no scrolling).
    @Published var scale: Double { didSet { d.set(scale, forKey: k + "scale") } }
    @Published var toast = ""

    init() {
        lastPage = d.integer(forKey: k + "last")
        bookmark = d.integer(forKey: k + "bookmark")
        let sc = d.double(forKey: k + "scale")
        scale = sc > 0 ? sc : 1
    }

    func read(_ p: Int) {
        let x = max(1, min(MsQuran.pageCount, p))
        page = x
        lastPage = x
        open = MsOpen(id: x)
    }
    func toggleBookmark() {
        if bookmark == page { bookmark = 0; flash("أزلت العلامة") } else { bookmark = page; flash("حفظت العلامة على صفحة " + String(page)) }
    }
    func flash(_ t: String) {
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in if self?.toast == t { self?.toast = "" } }
    }
    var suras: [Int] {
        let q = MsText.norm(MsText.western(query.trimmingCharacters(in: .whitespaces)))
        if q.isEmpty { return Array(1...114) }
        if let n = Int(q) { return (1...114).filter { String($0).hasPrefix(String(n)) } }
        return (1...114).filter { MsText.norm(MsQuran.suras[$0 - 1].name).contains(q) }
    }
    func surahOfPage(_ p: Int) -> Int { MsQuran.pages[max(0, min(603, p - 1))].0 }
}

/// «المصحف» — the button's single entry view.
public struct MushafView: View {
    @StateObject private var m = MsModel()
    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                hero
                MsSearch(placeholder: "ابحث باسم السورة أو رقمها", text: $m.query)
                HStack(spacing: 8) {
                    ForEach(MsTab.allCases) { t in
                        MsChip(title: t.title, selected: m.tab == t) { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { m.tab = t } }
                    }
                    Spacer()
                    jumpBox
                }
                if m.tab == .suras {
                    let xs = m.suras
                    if xs.isEmpty {
                        MsEmpty(icon: "magnifyingglass", title: "ما لقينا سورة بهالاسم", message: "جرّب جزء من الاسم، مثل: البقرة، يس، الملك، أو رقمها.")
                    }
                    ForEach(xs, id: \.self) { s in suraRow(s) }
                } else {
                    ForEach(1...30, id: \.self) { j in juzRow(j) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .animation(.easeOut(duration: 0.2), value: m.query)
        }
        .background(MsTheme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "المصحف"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $m.open) { _ in MsReader(m: m) }
        #if DEBUG
        .onAppear { // CI screenshots only: "-ciMushafPage N" opens that page
            let p = UserDefaults.standard.integer(forKey: "ciMushafPage")
            if p > 0, m.open == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { m.read(p) } }
        }
        #endif
        .tint(MsTheme.accent)
        .msRTL()
    }

    private var hero: some View {
        let has = m.lastPage > 0
        let s = m.surahOfPage(max(1, m.lastPage))
        return MsHero(title: "المصحف", subtitle: has ? "آخر قراءة: سورة " + MsQuran.suras[s - 1].name + "\nصفحة " + String(m.lastPage) + " · الجزء " + String(MsQuran.juzOf(MsQuran.pages[m.lastPage - 1].0, MsQuran.pages[m.lastPage - 1].1)) : "المصحف كامل برسم المصحف العثماني\n114 سورة · 604 صفحة") {
            Button { m.read(has ? m.lastPage : 1) } label: {
                VStack(spacing: 4) {
                    MsIcon(kind: "book", color: .white, size: 28)
                    Text(verbatim: has ? "تابع" : "ابدأ").font(.subheadline.weight(.bold)).foregroundColor(.white)
                }
                .frame(width: 76, height: 76)
                .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(MsPress())
        }
        .overlay(alignment: .bottomLeading) {
            if m.bookmark > 0 {
                Button { m.read(m.bookmark) } label: {
                    Label { Text(verbatim: "العلامة: صفحة " + String(m.bookmark)) } icon: { Image(systemName: "bookmark.fill") }
                        .font(.caption.weight(.semibold)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.18)))
                }
                .buttonStyle(MsPress())
                .padding(14)
            }
        }
    }

    private var jumpBox: some View {
        HStack(spacing: 6) {
            TextField(text: $m.jump) { Text(verbatim: "صفحة") }
                .keyboardType(.numberPad)
                .frame(width: 54)
                .multilineTextAlignment(.center)
            Button {
                if let p = Int(MsText.western(m.jump)), p >= 1, p <= 604 { m.read(p); m.jump = "" } else { m.flash("اكتب رقم صفحة من 1 إلى 604") }
            } label: { Image(systemName: "arrow.left.circle.fill").font(.system(size: 22)) }
            .buttonStyle(MsPress())
            .accessibilityLabel(Text(verbatim: "اذهب للصفحة"))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(MsTheme.card))
        .overlay(Capsule().stroke(MsTheme.line, lineWidth: 0.6))
    }

    private func numBadge(_ n: Int) -> some View {
        Text(verbatim: String(n))
            .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MsTheme.gradient))
    }

    private func suraRow(_ s: Int) -> some View {
        let x = MsQuran.suras[s - 1]
        let p = MsQuran.page(s, 1)
        return Button { m.read(p) } label: {
            MsCard(padding: 12) {
                HStack(spacing: 12) {
                    numBadge(s)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "سورة " + x.name).font(.headline).foregroundColor(.primary)
                        Text(verbatim: (x.makki ? "مكية" : "مدنية") + " · " + String(x.count) + " آية").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(verbatim: "ص " + String(p)).font(.subheadline.weight(.semibold)).foregroundColor(MsTheme.accent)
                        if m.lastPage > 0 && m.surahOfPage(m.lastPage) == s {
                            Text(verbatim: "آخر قراءة").font(.caption2.weight(.semibold)).foregroundColor(MsTheme.gold)
                        }
                    }
                }
            }
        }
        .buttonStyle(MsPress())
    }

    private func juzRow(_ j: Int) -> some View {
        let st = MsQuran.juz[j - 1]
        let p = MsQuran.page(st.0, st.1)
        return Button { m.read(p) } label: {
            MsCard(padding: 12) {
                HStack(spacing: 12) {
                    numBadge(j)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "الجزء " + String(j)).font(.headline).foregroundColor(.primary)
                        Text(verbatim: "يبدأ من سورة " + MsQuran.suras[st.0 - 1].name + "، آية " + String(st.1)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(verbatim: "ص " + String(p)).font(.subheadline.weight(.semibold)).foregroundColor(MsTheme.accent)
                }
            }
        }
        .buttonStyle(MsPress())
    }
}

/// Page-by-page reader (swipe like a real Mushaf).
struct MsReader: View {
    @ObservedObject var m: MsModel
    @Environment(\.dismiss) private var dismiss
    @GestureState private var pinch: CGFloat = 1
    static let minScale = 0.6
    static let maxScale = 2.2

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                TabView(selection: $m.page) {
                    ForEach(1...MsQuran.pageCount, id: \.self) { p in
                        MsPageView(page: p, scale: min(Self.maxScale, max(Self.minScale, m.scale * Double(pinch)))).tag(p)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($pinch) { v, s, _ in s = v }
                        .onEnded { v in m.scale = min(Self.maxScale, max(Self.minScale, m.scale * Double(v))) }
                )
                bottomBar
                if !m.toast.isEmpty {
                    Text(verbatim: m.toast).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(MsTheme.gradient))
                        .padding(.bottom, 96)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: m.toast)
            .background(MsTheme.paper.ignoresSafeArea())
            .navigationTitle(Text(verbatim: "سورة " + MsQuran.suras[m.surahOfPage(m.page) - 1].name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)) }
                        .accessibilityLabel(Text(verbatim: "إغلاق"))
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { m.scale = max(Self.minScale, ((m.scale - 0.1) * 1000).rounded() / 1000) } label: { Image(systemName: "textformat.size.smaller") }
                    Button { m.scale = min(Self.maxScale, ((m.scale + 0.1) * 1000).rounded() / 1000) } label: { Image(systemName: "textformat.size.larger") }
                    Button { withAnimation { m.toggleBookmark() } } label: { Image(systemName: m.bookmark == m.page ? "bookmark.fill" : "bookmark") }
                        .accessibilityLabel(Text(verbatim: "علامة"))
                }
            }
        }
        .tint(MsTheme.accent)
        .msRTL()
    }

    private var bottomBar: some View {
        let st = MsQuran.pages[m.page - 1]
        return HStack(spacing: 12) {
            Text(verbatim: "الجزء " + String(MsQuran.juzOf(st.0, st.1))).font(.caption.weight(.semibold))
            Slider(value: Binding(get: { Double(m.page) }, set: { m.page = Int($0.rounded()) }), in: 1...604, step: 1)
            Text(verbatim: String(m.page) + " / 604").font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
}

struct MsPageView: View {
    let page: Int
    /// 1 = the size that fits the whole page; above 1 the page scrolls.
    let scale: Double

    private struct Seg: Identifiable {
        let id: Int
        let surah: Int
        let header: Bool
        let text: String
        var basmala: String? = nil
    }

    private var segs: [Seg] {
        let q = MsQuran.shared
        var out: [Seg] = []
        var cur = ""
        var curS = 0
        for (s, a) in MsQuran.ayahs(onPage: page) {
            if s != curS || a == 1 {
                if !cur.isEmpty { out.append(Seg(id: out.count, surah: curS, header: false, text: cur)); cur = "" }
                curS = s
                if a == 1 { out.append(Seg(id: out.count, surah: s, header: true, text: "", basmala: q.split(s, a).basmala)) }
            }
            cur += (cur.isEmpty ? "" : " ") + q.split(s, a).rest + " " + MsQuran.marker(a)
        }
        if !cur.isEmpty { out.append(Seg(id: out.count, surah: curS, header: false, text: cur)) }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(120, geo.size.width - 36)
            let h = max(120, geo.size.height - MsFit.chrome)
            let fit = MsFit.size(page: page, width: w, height: h, parts: fitParts)
            let size = CGFloat(fit.size) * CGFloat(scale)
            if scale > 1.0001 || !fit.fits {
                ScrollView { content(size) }
            } else {
                content(size).frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
    }

    /// What has to fit: the surah title boxes, the basmalas and the running text, in page order.
    private var fitParts: [MsFit.Part] {
        var out: [MsFit.Part] = []
        for g in segs {
            if g.header {
                out.append(.header)
                if let b = g.basmala { out.append(.basmala(b)) }
            } else {
                out.append(.text(g.text))
            }
        }
        return out
    }

    private func content(_ fontSize: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text(verbatim: "سورة " + MsQuran.suras[MsQuran.pages[page - 1].0 - 1].name)
                Spacer()
                Text(verbatim: String(page))
            }
            .font(.caption.weight(.semibold)).foregroundColor(MsTheme.gold)
            ForEach(segs) { g in
                if g.header {
                    VStack(spacing: 10) {
                        Text(verbatim: "سورة " + MsQuran.suras[g.surah - 1].name)
                            .font(.headline).foregroundColor(MsTheme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MsTheme.soft))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MsTheme.gold.opacity(0.6), lineWidth: 1))
                        if let b = g.basmala {
                            Text(verbatim: b).font(MsFont.quran(fontSize)).foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text(verbatim: g.text)
                        .font(MsFont.quran(fontSize))
                        .lineSpacing(fontSize * 0.55)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: MsFit.bottomBar)
        }
        .padding(.horizontal, 18).padding(.top, 10)
    }
}

/// The text size at which a whole page fits the space above the bottom bar (measured with the same font and spacing).
enum MsFit {
    enum Part { case header, basmala(String), text(String) }
    /// Room kept for the page-number line, the top padding and the floating slider bar.
    static let bottomBar: CGFloat = 78
    static let chrome: CGFloat = 10 + 18 + 14 + bottomBar
    static let minSize: CGFloat = 14
    static let maxSize: CGFloat = 40
    private static var cache: [String: (size: Double, fits: Bool)] = [:]

    static func size(page: Int, width: CGFloat, height avail: CGFloat, parts: [Part]) -> (size: Double, fits: Bool) {
        let key = "\(page)-\(Int(width))-\(Int(avail))"
        if let c = cache[key] { return c }
        var lo = minSize, hi = maxSize
        let fits = Self.height(of: parts, size: lo, width: width) <= avail
        if fits {
            if Self.height(of: parts, size: hi, width: width) <= avail { lo = hi }
            else {
                for _ in 0..<14 {
                    let mid = (lo + hi) / 2
                    if Self.height(of: parts, size: mid, width: width) <= avail { lo = mid } else { hi = mid }
                }
            }
        }
        let r = (size: Double((lo * 4).rounded(.down) / 4), fits: fits)
        cache[key] = r
        return r
    }

    static func height(of parts: [Part], size: CGFloat, width: CGFloat) -> CGFloat {
        var total: CGFloat = 0
        for (i, p) in parts.enumerated() {
            if i > 0 {
                if case .basmala = p { total += 10 } else { total += 14 }
            }
            switch p {
            case .header: total += 22 + 20
            case .basmala(let b): total += measure(b, size: size, width: width, spacing: 0)
            case .text(let t): total += measure(t, size: size, width: width, spacing: size * 0.55)
            }
        }
        return total * 1.04 + 4
    }

    static func measure(_ s: String, size: CGFloat, width: CGFloat, spacing: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        MsFont.register()
        let font = UIFont(name: MsFont.quranName, size: size) ?? UIFont(name: "AmiriQuran-Regular", size: size) ?? UIFont.systemFont(ofSize: size)
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = spacing
        ps.alignment = .center
        ps.baseWritingDirection = .rightToLeft
        let a = NSAttributedString(string: s, attributes: [.font: font, .paragraphStyle: ps])
        let r = a.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(r.height)
        #else
        return size * 1.6 * CGFloat(max(1, s.count / 40))
        #endif
    }
}
