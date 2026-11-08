import SwiftUI

enum HfTab: Int, CaseIterable, Identifiable {
    case session, progress, review
    var id: Int { rawValue }
    var title: String {
        switch self { case .session: return "جلسة الحفظ"; case .progress: return "تقدّمي"; case .review: return "المراجعة" }
    }
}
enum HfMode: Int, CaseIterable, Identifiable {
    case read, hide, words, recite
    var id: Int { rawValue }
    var title: String {
        switch self { case .read: return "قراءة"; case .hide: return "إخفاء الآيات"; case .words: return "اختبار الكلمات"; case .recite: return "تسميع" }
    }
}

/// Memorisation state, saved in UserDefaults ("alsalmi.hifz.*").
final class HfModel: ObservableObject {
    private let d = UserDefaults.standard
    private let k = "alsalmi.hifz."
    @Published var tab: HfTab = .session
    @Published var mode: HfMode = .read
    @Published var surah: Int { didSet { d.set(surah, forKey: k + "surah") } }
    @Published var from: Int { didSet { d.set(from, forKey: k + "from") } }
    @Published var to: Int { didSet { d.set(to, forKey: k + "to") } }
    @Published var target: Int { didSet { d.set(target, forKey: k + "target") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: k + "font") } }
    @Published var memorised: Set<Int> { didSet { d.set(Array(memorised), forKey: k + "mem") } }
    @Published var weak: Set<Int> { didSet { d.set(Array(weak), forKey: k + "weak") } }
    @Published var repeats: [String: Int] { didSet { d.set(repeats, forKey: k + "rep") } }
    @Published var revealed: Set<Int> = []
    @Published var wordsShown: [Int: Int] = [:]
    @Published var showPicker = false
    @Published var query = ""
    @Published var progQuery = ""

    init() {
        let s = d.integer(forKey: k + "surah")
        surah = (1...114).contains(s) ? s : 67
        let f = d.integer(forKey: k + "from"); from = f > 0 ? f : 1
        let t = d.integer(forKey: k + "to"); to = t > 0 ? t : 5
        let g = d.integer(forKey: k + "target"); target = g > 0 ? g : 5
        let fs = d.double(forKey: k + "font"); fontSize = fs > 0 ? fs : 24
        memorised = Set((d.array(forKey: k + "mem") as? [Int]) ?? [])
        weak = Set((d.array(forKey: k + "weak") as? [Int]) ?? [])
        repeats = (d.dictionary(forKey: k + "rep") as? [String: Int]) ?? [:]
        clamp()
    }

    var count: Int { HfQuran.suras[surah - 1].count }
    func clamp() {
        if from < 1 { from = 1 }
        if from > count { from = count }
        if to < from { to = from }
        if to > count { to = count }
    }
    func pick(_ s: Int) {
        surah = s; from = 1; to = min(HfQuran.suras[s - 1].count, 5); resetView(); showPicker = false
    }
    func focus(_ key: Int) {
        surah = key / 1000; from = key % 1000; to = key % 1000; resetView(); tab = .session; mode = .words
    }
    func resetView() { revealed = []; wordsShown = [:] }
    var range: [Int] { Array(from...max(from, to)) }

    func key(_ a: Int) -> Int { HfQuran.key(surah, a) }
    func reps(_ k: Int) -> Int { repeats[String(k)] ?? 0 }
    /// true when the target was just reached
    func bump(_ k: Int) -> Bool { let n = reps(k) + 1; repeats[String(k)] = n; return n == target }
    func resetReps(_ k: Int) { repeats[String(k)] = nil }
    func toggleMem(_ k: Int) {
        if memorised.contains(k) { memorised.remove(k) } else { memorised.insert(k); weak.remove(k) }
    }
    func toggleWeak(_ k: Int) { if weak.contains(k) { weak.remove(k) } else { weak.insert(k) } }

    func memCount(_ s: Int) -> Int { memorised.filter { $0 / 1000 == s }.count }
    var total: Int { memorised.count }

    var surasFiltered: [Int] {
        let q = HfText.norm(HfText.western(query.trimmingCharacters(in: .whitespaces)))
        if q.isEmpty { return Array(1...114) }
        if let n = Int(q) { return (1...114).filter { String($0).hasPrefix(String(n)) } }
        return (1...114).filter { HfText.norm(HfQuran.suras[$0 - 1].name).contains(q) }
    }
    var progressSuras: [Int] {
        let q = HfText.norm(progQuery.trimmingCharacters(in: .whitespaces))
        let xs = (1...114).filter { q.isEmpty || HfText.norm(HfQuran.suras[$0 - 1].name).contains(q) }
        return xs.sorted { (memCount($0) > 0 ? 0 : 1, $0) < (memCount($1) > 0 ? 0 : 1, $1) }
    }
    var weakList: [Int] { weak.sorted() }

    /// words of an ayah (pause marks stay attached to the word before them)
    static func words(_ t: String) -> [String] {
        var out: [String] = []
        for w in t.split(separator: " ") {
            let hasLetter = w.unicodeScalars.contains { (0x0621...0x064A).contains($0.value) || (0x0671...0x06D3).contains($0.value) }
            if !hasLetter, !out.isEmpty { out[out.count - 1] += " " + w } else { out.append(String(w)) }
        }
        return out
    }
}

/// «وضع الحفظ» — the button's single entry view (the whole Mushaf).
public struct HifzView: View {
    @StateObject private var m = HfModel()
    @StateObject private var rec = HfReciter()
    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(HfTab.allCases) { t in
                        HfChip(title: t.title + (t == .review && !m.weak.isEmpty ? "  " + String(m.weak.count) : ""), selected: m.tab == t) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { m.tab = t }
                        }
                    }
                    Spacer(minLength: 0)
                }
                switch m.tab {
                case .session: session
                case .progress: progress
                case .review: review
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: m.mode)
        }
        .background(HfTheme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "وضع الحفظ"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { m.fontSize = max(18, m.fontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                Button { m.fontSize = min(42, m.fontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
            }
        }
        .sheet(isPresented: $m.showPicker) { NavigationStack { picker }.hfRTL() }
        .modifier(HfReciteHooks(m: m, rec: rec))
        .tint(HfTheme.accent)
        .hfRTL()
    }

    // MARK: session
    private var session: some View {
        let mem = m.memCount(m.surah)
        return VStack(spacing: 14) {
            HfHero(title: "سورة " + HfQuran.suras[m.surah - 1].name, subtitle: "حفظت " + String(mem) + " من " + String(m.count) + " آية\nالآيات " + String(m.from) + " – " + String(m.to)) {
                HfRing(progress: Double(mem) / Double(max(1, m.count)), size: 80, line: 8) {
                    Text(verbatim: String(Int((Double(mem) * 100 / Double(max(1, m.count))).rounded())) + "%").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.white)
                }
            }
            HfCard {
                VStack(spacing: 12) {
                    Button { m.query = ""; m.showPicker = true } label: {
                        HStack {
                            Text(verbatim: "السورة").foregroundColor(.secondary)
                            Spacer()
                            Text(verbatim: String(m.surah) + ". " + HfQuran.suras[m.surah - 1].name).font(.headline).foregroundColor(HfTheme.accent)
                            Image(systemName: "chevron.down").font(.caption).foregroundColor(HfTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                    Stepper(value: Binding(get: { m.from }, set: { m.from = $0; m.clamp(); m.resetView() }), in: 1...m.count) {
                        HStack { Text(verbatim: "من آية"); Spacer(); Text(verbatim: String(m.from)).bold().monospacedDigit() }
                    }
                    Stepper(value: Binding(get: { m.to }, set: { m.to = $0; m.clamp(); m.resetView() }), in: m.from...m.count) {
                        HStack { Text(verbatim: "إلى آية"); Spacer(); Text(verbatim: String(m.to)).bold().monospacedDigit() }
                    }
                    Divider()
                    HStack(spacing: 6) {
                        Text(verbatim: "التكرار").foregroundColor(.secondary)
                        Spacer()
                        ForEach([3, 5, 7, 10, 20], id: \.self) { n in
                            HfChip(title: String(n), selected: m.target == n) { m.target = n }
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HfMode.allCases) { x in
                        HfChip(title: x.title, selected: m.mode == x) { m.mode = x; m.resetView() }
                    }
                }
                .padding(.vertical, 2)
            }
            if m.mode == .recite { HfRecitePanel(r: rec) }
            ForEach(m.range, id: \.self) { a in ayahCard(a) }
            if m.to < m.count {
                Button { m.from = m.to + 1; m.to = min(m.count, m.to + 5); m.resetView() } label: {
                    Label { Text(verbatim: "المقطع التالي") } icon: { Image(systemName: "arrow.left") }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Capsule().fill(HfTheme.soft))
                }
                .buttonStyle(HfPress())
            }
        }
    }

    private func ayahCard(_ a: Int) -> some View {
        let k = m.key(a)
        let sp = HfQuran.shared.split(m.surah, a)
        let words = HfModel.words(sp.rest)
        let shown = m.wordsShown[k] ?? 0
        let reps = m.reps(k)
        let mem = m.memorised.contains(k)
        let weak = m.weak.contains(k)
        return HfCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(verbatim: "آية " + String(a)).font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(HfTheme.soft)).foregroundColor(HfTheme.accent)
                    if mem { Label { Text(verbatim: "محفوظة") } icon: { Image(systemName: "checkmark.circle.fill") }.font(.caption.weight(.semibold)).foregroundColor(HfTheme.good) }
                    if weak { Label { Text(verbatim: "للمراجعة") } icon: { Image(systemName: "flag.fill") }.font(.caption.weight(.semibold)).foregroundColor(HfTheme.warn) }
                    Spacer()
                }
                if let b = sp.basmala {
                    Text(verbatim: b).font(HfFont.quran(m.fontSize - 2)).frame(maxWidth: .infinity)
                }
                Group {
                    switch m.mode {
                    case .read:
                        Text(verbatim: sp.rest + " " + HfQuran.marker(a)).font(HfFont.quran(m.fontSize))
                    case .hide:
                        if m.revealed.contains(k) {
                            Text(verbatim: sp.rest + " " + HfQuran.marker(a)).font(HfFont.quran(m.fontSize)).transition(.opacity)
                        } else {
                            Text(verbatim: sp.rest).font(HfFont.quran(m.fontSize)).redacted(reason: .placeholder)
                                .overlay(Text(verbatim: "اضغط لإظهار الآية").font(.footnote.weight(.semibold)).foregroundColor(HfTheme.accent)
                                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(HfTheme.card)))
                        }
                    case .words:
                        wordText(words, shown, a)
                    case .recite:
                        reciteText(words, a)
                    }
                }
                .lineSpacing(m.fontSize * 0.55)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.25)) {
                        if m.mode == .hide { if m.revealed.contains(k) { m.revealed.remove(k) } else { m.revealed.insert(k) } }
                        if m.mode == .words { m.wordsShown[k] = min(words.count, shown + 1) }
                    }
                }
                if m.mode == .words {
                    HStack(spacing: 8) {
                        smallButton("كلمة", "plus") { withAnimation { m.wordsShown[k] = min(words.count, shown + 1) } }
                        smallButton("الآية", "eye") { withAnimation { m.wordsShown[k] = words.count } }
                        smallButton("من جديد", "arrow.counterclockwise") { withAnimation { m.wordsShown[k] = 0 } }
                        Spacer()
                        Text(verbatim: String(shown) + "/" + String(words.count)).font(.caption).foregroundColor(.secondary).monospacedDigit()
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        let hit = withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { m.bump(k) }
                        hit ? HfHaptics.success() : HfHaptics.tap()
                    } label: {
                        HfRing(progress: Double(min(reps, m.target)) / Double(m.target), size: 54, line: 5, onGradient: false) {
                            VStack(spacing: 0) {
                                Text(verbatim: String(reps)).font(.system(size: 17, weight: .bold, design: .rounded)).contentTransition(.numericText())
                                Text(verbatim: "تكرار").font(.system(size: 8)).foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(HfPress())
                    .contextMenu { Button { m.resetReps(k) } label: { Text(verbatim: "تصفير العدّاد") } }
                    Spacer()
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { m.toggleWeak(k) } } label: {
                        Label { Text(verbatim: weak ? "شلها من المراجعة" : "ضعيفة") } icon: { Image(systemName: weak ? "flag.slash" : "flag") }
                            .font(.footnote.weight(.semibold)).foregroundColor(HfTheme.warn)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Capsule().fill(HfTheme.warn.opacity(0.12)))
                    }
                    .buttonStyle(HfPress())
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { m.toggleMem(k) }; HfHaptics.success() } label: {
                        Label { Text(verbatim: mem ? "محفوظة" : "حفظتها") } icon: { Image(systemName: mem ? "checkmark.circle.fill" : "checkmark.circle") }
                            .font(.footnote.weight(.bold)).foregroundColor(mem ? HfTheme.bg : HfTheme.good)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Capsule().fill(mem ? HfTheme.good : HfTheme.good.opacity(0.12)))
                    }
                    .buttonStyle(HfPress())
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(reps >= m.target && !mem ? HfTheme.accent.opacity(0.6) : Color.clear, lineWidth: 1.2))
    }

    private func wordText(_ words: [String], _ shown: Int, _ a: Int) -> Text {
        var t = Text(verbatim: "")
        for (i, w) in words.enumerated() {
            let sep = i == 0 ? "" : " "
            if i < shown {
                t = t + Text(verbatim: sep + w).font(HfFont.quran(m.fontSize))
            } else {
                t = t + Text(verbatim: sep).font(HfFont.quran(m.fontSize)) + Text(verbatim: w).font(HfFont.quran(m.fontSize)).foregroundColor(.clear).underline(true, color: HfTheme.accent.opacity(0.55))
            }
        }
        if shown >= words.count { t = t + Text(verbatim: " " + HfQuran.marker(a)).font(HfFont.quran(m.fontSize)) }
        return t
    }

    /// «تسميع»: the words he has recited so far appear in place; the rest stay hidden; a missed word is underlined.
    private func reciteText(_ words: [String], _ a: Int) -> Text {
        let shown = rec.revealed(ayah: a)
        let wrong = rec.wrongIndex(ayah: a)
        var t = Text(verbatim: "")
        for (i, w) in words.enumerated() {
            let sep = i == 0 ? "" : " "
            if shown.contains(i) {
                t = t + Text(verbatim: sep + w).font(HfFont.quran(m.fontSize))
            } else {
                let c = i == wrong ? HfTheme.warn : HfTheme.accent.opacity(0.55)
                t = t + Text(verbatim: sep).font(HfFont.quran(m.fontSize)) + Text(verbatim: w).font(HfFont.quran(m.fontSize)).foregroundColor(.clear).underline(true, color: c)
            }
        }
        if !words.isEmpty && shown.count >= words.filter({ !HfMatch.norm($0).isEmpty }).count { t = t + Text(verbatim: " " + HfQuran.marker(a)).font(HfFont.quran(m.fontSize)) }
        return t
    }

    private func smallButton(_ t: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(verbatim: t) } icon: { Image(systemName: icon) }
                .font(.caption.weight(.semibold)).foregroundColor(HfTheme.accent)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(HfTheme.soft))
        }
        .buttonStyle(HfPress())
    }

    // MARK: progress
    private var progress: some View {
        VStack(spacing: 14) {
            HfHero(title: "محفوظك من القرآن", subtitle: String(m.total) + " آية من 6236\n" + String((1...114).filter { m.memCount($0) == HfQuran.suras[$0 - 1].count }.count) + " سورة كاملة") {
                HfRing(progress: Double(m.total) / 6236.0, size: 84, line: 8) {
                    Text(verbatim: String(format: "%.1f%%", Double(m.total) * 100 / 6236.0)).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white)
                }
            }
            HfSearch(placeholder: "ابحث عن سورة", text: $m.progQuery)
            if m.total == 0 && m.progQuery.isEmpty {
                HfCard { HfEmpty(icon: "checkmark.circle", title: "ما علّمت شي محفوظ للحين", message: "في جلسة الحفظ اضغط «حفظتها» تحت أي آية، ويطلع تقدّمك هنا لكل سورة.") }
            }
            ForEach(m.progressSuras, id: \.self) { s in
                let c = m.memCount(s), n = HfQuran.suras[s - 1].count
                Button { m.pick(s); m.tab = .session } label: {
                    HfCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(verbatim: String(s) + ". سورة " + HfQuran.suras[s - 1].name).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                Spacer()
                                Text(verbatim: String(c) + " / " + String(n)).font(.caption.weight(.semibold)).monospacedDigit().foregroundColor(c == n ? HfTheme.good : .secondary)
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(HfTheme.soft)
                                    Capsule().fill(HfTheme.gradient).frame(width: g.size.width * CGFloat(c) / CGFloat(max(1, n)))
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                }
                .buttonStyle(HfPress())
            }
        }
    }

    // MARK: review
    private var review: some View {
        VStack(spacing: 14) {
            HfHero(title: "المراجعة", subtitle: m.weak.isEmpty ? "الآيات اللي تعلّمها «ضعيفة» تجي هنا" : String(m.weak.count) + " آية تحتاج مراجعة") {
                HfRing(progress: 1, size: 70, line: 7) { HfIcon(kind: "book", color: .white, size: 26) }
            }
            if m.weak.isEmpty {
                HfCard { HfEmpty(icon: "flag", title: "ما عندك آيات ضعيفة", message: "إذا تلخبطت في آية وقت الحفظ اضغط «ضعيفة»، وتلقاها هنا تراجعها لحالها.") }
            }
            ForEach(m.weakList, id: \.self) { k in
                let s = k / 1000, a = k % 1000
                HfCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: "سورة " + HfQuran.suras[s - 1].name + " · آية " + String(a)).font(.caption.weight(.bold)).foregroundColor(HfTheme.accent)
                        Text(verbatim: HfQuran.shared.split(s, a).rest).font(HfFont.quran(m.fontSize - 2)).lineSpacing(10).lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button { m.focus(k) } label: {
                                Label { Text(verbatim: "اختبرني") } icon: { Image(systemName: "play.fill") }
                                    .font(.footnote.weight(.bold)).foregroundColor(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(HfTheme.gradient))
                            }
                            .buttonStyle(HfPress())
                            Spacer()
                            Button { withAnimation { m.weak.remove(k); m.memorised.insert(k) } } label: {
                                Label { Text(verbatim: "ضبطتها") } icon: { Image(systemName: "checkmark") }
                                    .font(.footnote.weight(.semibold)).foregroundColor(HfTheme.good)
                                    .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(HfTheme.good.opacity(0.12)))
                            }
                            .buttonStyle(HfPress())
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: m.weak)
    }

    private var picker: some View {
        List {
            Section { HfSearch(placeholder: "اسم السورة أو رقمها", text: $m.query).listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)) }
            if m.surasFiltered.isEmpty { Section { HfEmpty(icon: "magnifyingglass", title: "ما لقينا السورة", message: "جرّب جزء من الاسم أو رقمها.") } }
            Section {
                ForEach(m.surasFiltered, id: \.self) { s in
                    Button { m.pick(s) } label: {
                        HStack {
                            Text(verbatim: String(s) + ". سورة " + HfQuran.suras[s - 1].name).foregroundColor(.primary)
                            Spacer()
                            Text(verbatim: String(m.memCount(s)) + "/" + String(HfQuran.suras[s - 1].count)).font(.caption).foregroundColor(.secondary).monospacedDigit()
                            if s == m.surah { Image(systemName: "checkmark").foregroundColor(HfTheme.accent) }
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: "اختر السورة"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button { m.showPicker = false } label: { Text(verbatim: "إغلاق") } } }
    }
}

/// «تسميع» wiring, kept apart from the main view's modifier chain: loads the chosen range, stops the mic when leaving.
private struct HfReciteHooks: ViewModifier {
    @ObservedObject var m: HfModel
    @ObservedObject var rec: HfReciter
    private var rangeId: String { String(m.surah) + ":" + String(m.from) + ":" + String(m.to) + ":" + String(m.mode.rawValue) }
    func body(content: Content) -> some View {
        content
            .task(id: rangeId) { reload() }
            .onDisappear { rec.stop() }
            .onAppear {
                #if DEBUG
                if UserDefaults.standard.string(forKey: "ciHifzMode") == "recite" { m.mode = .recite } // CI screenshots only
                #endif
            }
    }
    private func reload() {
        guard m.mode == .recite else { rec.stop(); return }
        let s = m.surah
        rec.load(surah: s, ayahs: m.range) { a in HfModel.words(HfQuran.shared.split(s, a).rest) }
        #if DEBUG
        let n = UserDefaults.standard.integer(forKey: "ciReciteDemo") // CI screenshots only
        if n > 0 { rec.demo(n) }
        #endif
    }
}
