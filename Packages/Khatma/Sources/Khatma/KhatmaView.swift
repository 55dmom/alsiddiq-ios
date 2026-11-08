import SwiftUI

struct KhOpen: Identifiable { let id: Int }

/// Plan and progress, saved in UserDefaults ("alsalmi.khatma.*").
final class KhModel: ObservableObject {
    private let d = UserDefaults.standard
    private let k = "alsalmi.khatma."
    @Published var days: Int { didSet { d.set(days, forKey: k + "days") } }
    @Published var startDay: String { didSet { d.set(startDay, forKey: k + "start") } }
    @Published var startPage: Int { didSet { d.set(startPage, forKey: k + "startPage") } }
    /// next page to read (605 = finished)
    @Published var pointer: Int { didSet { d.set(pointer, forKey: k + "pointer") } }
    @Published var log: [String: Int] { didSet { d.set(log, forKey: k + "log") } }
    @Published var completed: Int { didSet { d.set(completed, forKey: k + "completed") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: k + "font") } }
    @Published var showSetup = false
    @Published var draftDays = 30
    @Published var draftStart = 1
    @Published var open: KhOpen? = nil
    @Published var readerPage = 1
    @Published var readerRange: ClosedRange<Int> = 1...1
    @Published var celebrate = false

    init() {
        days = d.integer(forKey: k + "days")
        startDay = d.string(forKey: k + "start") ?? ""
        let sp = d.integer(forKey: k + "startPage")
        startPage = sp > 0 ? sp : 1
        let p = d.integer(forKey: k + "pointer")
        pointer = p > 0 ? p : 1
        log = (d.dictionary(forKey: k + "log") as? [String: Int]) ?? [:]
        completed = d.integer(forKey: k + "completed")
        let f = d.double(forKey: k + "font")
        fontSize = f > 0 ? f : 24
    }

    var hasPlan: Bool { days > 0 && !startDay.isEmpty }
    var finished: Bool { pointer > 604 }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func date(_ key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
    var today: String { KhModel.dayKey(Date()) }

    /// 1-based day of the plan
    var dayNumber: Int {
        guard let s = KhModel.date(startDay), let t = KhModel.date(today) else { return 1 }
        return (Calendar(identifier: .gregorian).dateComponents([.day], from: s, to: t).day ?? 0) + 1
    }
    var totalPages: Int { 604 - startPage + 1 }
    var readPages: Int { max(0, min(604, pointer - 1) - startPage + 1) }
    var progress: Double { Double(readPages) / Double(max(1, totalPages)) }
    var doneToday: Int { log[today] ?? 0 }

    /// pages per day, re-balanced from today on
    var dailyPages: Int {
        let remDays = max(1, days - dayNumber + 1)
        let remPages = max(0, 604 - pointer + 1 + doneToday)
        return max(1, Int((Double(remPages) / Double(remDays)).rounded(.up)))
    }
    var portion: ClosedRange<Int> {
        let a = min(604, pointer)
        return a...min(604, a + dailyPages - 1)
    }
    /// pages you should have read before today
    var expected: Int { min(totalPages, Int((Double(totalPages) * Double(min(days, dayNumber - 1)) / Double(max(1, days))).rounded(.down))) }
    var status: (String, Color) {
        if finished { return ("ختمت، ما شاء الله", KhTheme.good) }
        let diff = readPages - expected
        if diff >= 0 { return (diff > dailyPages ? "متقدّم على الخطة" : "ماشي على الخطة", KhTheme.good) }
        let behindDays = Int((Double(-diff) / Double(max(1, totalPages / max(1, days)))).rounded(.up))
        return ("متأخر " + (behindDays <= 1 ? "يوم" : String(behindDays) + " أيام") + " — ورد اليوم زاد شوي عشان تلحق", KhTheme.warn)
    }

    func begin() {
        days = max(1, draftDays); startPage = max(1, min(604, draftStart)); pointer = startPage
        startDay = today; log = [:]; showSetup = false
    }
    func markDone() {
        let r = portion
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            pointer = r.upperBound + 1
            log[today] = (log[today] ?? 0) + r.count
        }
        if finished {
            completed += 1
            celebrate = true
        }
    }
    func undoToday() {
        guard let n = log[today], n > 0 else { return }
        withAnimation { pointer = max(startPage, pointer - n); log[today] = nil }
    }
    func readPortion() {
        readerRange = portion
        readerPage = portion.lowerBound
        open = KhOpen(id: portion.lowerBound)
    }
    func juzText(_ pages: Int) -> String {
        let j = Double(pages) / 20.0
        if j >= 0.95 && j < 1.05 { return "جزء تقريباً" }
        if j < 1 { return j >= 0.45 && j < 0.55 ? "نصف جزء تقريباً" : "أقل من جزء" }
        return String(format: "%.1f", j) + " جزء تقريباً"
    }
    var recent: [(String, Int)] {
        log.sorted { $0.key > $1.key }.prefix(7).map { ($0.key, $0.value) }
    }
}

/// «ختمتي» — the button's single entry view.
public struct KhatmaView: View {
    @StateObject private var m = KhModel()
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if m.hasPlan { planBody } else { emptyBody }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(KhTheme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "ختمتي"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if m.hasPlan {
                ToolbarItem(placement: .primaryAction) {
                    Button { m.draftDays = m.days; m.draftStart = 1; m.showSetup = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel(Text(verbatim: "ختمة جديدة"))
                }
            }
        }
        .sheet(isPresented: $m.showSetup) { NavigationStack { setup }.khRTL() }
        .fullScreenCover(item: $m.open) { _ in KhReader(m: m) }
        .alert(Text(verbatim: "ما شاء الله، ختمت!"), isPresented: $m.celebrate) {
            Button { m.draftDays = m.days; m.draftStart = 1; m.showSetup = true } label: { Text(verbatim: "ختمة جديدة") }
            Button(role: .cancel) {} label: { Text(verbatim: "تمام") }
        } message: { Text(verbatim: "تقبّل الله منك. هذي ختمتك رقم " + String(m.completed) + ".") }
        .tint(KhTheme.accent)
        .khRTL()
    }

    private var emptyBody: some View {
        VStack(spacing: 16) {
            KhHero(title: "ختمتي", subtitle: "حدّد كم يوم تبي تختم فيه،\nوأقسم لك القرآن ورد يومي") {
                KhRing(progress: 0, size: 76) { KhIcon(kind: "book", color: .white, size: 30) }
            }
            KhCard {
                KhEmpty(icon: "calendar.badge.plus", title: "ما بدأت ختمة للحين", message: "اختر المدة (أسبوع، شهر، شهرين…) ويطلع لك كم صفحة وكم جزء تقرأ كل يوم، وتعلّم على ورد اليوم إذا خلصته.")
            }
            Button { m.showSetup = true } label: {
                Text(verbatim: "ابدأ ختمة").font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(KhTheme.gradient))
            }
            .buttonStyle(KhPress())
        }
    }

    private var planBody: some View {
        let r = m.portion
        let st = m.status
        return VStack(spacing: 16) {
            KhHero(title: m.finished ? "ختمت" : "اليوم " + String(min(m.dayNumber, m.days)) + " من " + String(m.days),
                   subtitle: String(m.readPages) + " من " + String(m.totalPages) + " صفحة\n" + (m.completed > 0 ? "ختماتك: " + String(m.completed) : "الله يعينك ويتقبّل")) {
                KhRing(progress: m.progress, size: 86, line: 8) {
                    Text(verbatim: String(Int((m.progress * 100).rounded())) + "%").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .contentTransition(.numericText())
                }
            }
            HStack(spacing: 8) {
                Circle().fill(st.1).frame(width: 9, height: 9)
                Text(verbatim: st.0).font(.subheadline.weight(.semibold)).foregroundColor(st.1)
                Spacer()
            }
            .padding(.horizontal, 4)
            if !m.finished { todayCard(r) }
            statsRow
            if !m.recent.isEmpty { historyCard }
        }
    }

    private func todayCard(_ r: ClosedRange<Int>) -> some View {
        let a = KhQuran.pages[r.lowerBound - 1]
        let bEnd = r.upperBound < 604 ? KhQuran.pages[r.upperBound] : (114, 7)
        let last = KhQuran.prev(bEnd.0, bEnd.1)
        return KhCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(verbatim: m.doneToday > 0 ? "ورد إضافي" : "ورد اليوم").font(.headline)
                    Spacer()
                    Text(verbatim: String(r.count) + " صفحة · " + m.juzText(r.count)).font(.subheadline.weight(.semibold)).foregroundColor(KhTheme.accent)
                }
                HStack(spacing: 10) {
                    endpoint("من", "سورة " + KhQuran.suras[a.0 - 1].name + " " + String(a.1), "ص " + String(r.lowerBound))
                    Image(systemName: "arrow.left").foregroundColor(.secondary)
                    endpoint("إلى", "سورة " + KhQuran.suras[last.0 - 1].name + " " + String(last.1), "ص " + String(r.upperBound))
                }
                HStack(spacing: 10) {
                    Button { m.readPortion() } label: {
                        Label { Text(verbatim: "اقرأ الورد") } icon: { Image(systemName: "book") }
                            .font(.subheadline.weight(.semibold)).foregroundColor(KhTheme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KhTheme.soft))
                    }
                    .buttonStyle(KhPress())
                    Button { KhHaptics.success(); m.markDone() } label: {
                        Label { Text(verbatim: m.doneToday > 0 ? "قرأته كذلك" : "قرأت ورد اليوم") } icon: { Image(systemName: "checkmark") }
                            .font(.subheadline.weight(.bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KhTheme.gradient))
                    }
                    .buttonStyle(KhPress())
                }
                if m.doneToday > 0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(KhTheme.good)
                        Text(verbatim: "قرأت اليوم " + String(m.doneToday) + " صفحة").font(.footnote).foregroundColor(.secondary)
                        Spacer()
                        Button { m.undoToday() } label: { Text(verbatim: "تراجع").font(.footnote.weight(.semibold)) }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func endpoint(_ t: String, _ s: String, _ p: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: t).font(.caption).foregroundColor(.secondary)
            Text(verbatim: s).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: p).font(.caption).foregroundColor(KhTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KhTheme.bg))
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat("باقي", String(max(0, 604 - m.pointer + 1)), "صفحة")
            stat("الأيام الباقية", String(max(0, m.days - m.dayNumber + 1)), "يوم")
            stat("الورد اليومي", String(m.dailyPages), "صفحة")
        }
    }
    private func stat(_ t: String, _ v: String, _ u: String) -> some View {
        KhCard(padding: 12) {
            VStack(spacing: 2) {
                Text(verbatim: t).font(.caption).foregroundColor(.secondary)
                Text(verbatim: v).font(.system(size: 22, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text(verbatim: u).font(.caption2).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var historyCard: some View {
        KhCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "آخر الأيام").font(.headline)
                ForEach(m.recent, id: \.0) { e in
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(KhTheme.good)
                        Text(verbatim: e.0).font(.subheadline).monospacedDigit()
                        Spacer()
                        Text(verbatim: String(e.1) + " صفحة").font(.subheadline.weight(.semibold)).foregroundColor(KhTheme.accent)
                    }
                }
            }
        }
    }

    private var setup: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([7, 10, 15, 20, 30, 40, 60, 90], id: \.self) { n in
                            KhChip(title: String(n) + " يوم", selected: m.draftDays == n) { m.draftDays = n }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Stepper(value: $m.draftDays, in: 1...365) {
                    HStack { Text(verbatim: "المدة"); Spacer(); Text(verbatim: String(m.draftDays) + " يوم").foregroundColor(.secondary).monospacedDigit() }
                }
            } header: { Text(verbatim: "خلال كم يوم تختم؟") }
            Section {
                Stepper(value: $m.draftStart, in: 1...604) {
                    HStack { Text(verbatim: "أبدأ من صفحة"); Spacer(); Text(verbatim: String(m.draftStart) + " — سورة " + KhQuran.suras[KhQuran.pages[m.draftStart - 1].0 - 1].name).foregroundColor(.secondary) }
                }
            } header: { Text(verbatim: "البداية") } footer: { Text(verbatim: "إذا كنت قارئ جزء من قبل، ابدأ من الصفحة اللي وقفت عندها.") }
            Section {
                let pages = 604 - m.draftStart + 1
                let per = Int((Double(pages) / Double(max(1, m.draftDays))).rounded(.up))
                HStack { Text(verbatim: "ورد كل يوم"); Spacer(); Text(verbatim: String(per) + " صفحة · " + m.juzText(per)).foregroundColor(KhTheme.accent).bold() }
                Button { m.begin() } label: { Text(verbatim: "ابدأ الختمة").bold() }
            }
        }
        .navigationTitle(Text(verbatim: "ختمة جديدة"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button { m.showSetup = false } label: { Text(verbatim: "إلغاء") } } }
    }
}

/// Reader limited to today's portion.
struct KhReader: View {
    @ObservedObject var m: KhModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TabView(selection: $m.readerPage) {
                ForEach(Array(m.readerRange), id: \.self) { p in
                    KhPageView(page: p, fontSize: m.fontSize).tag(p)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(KhTheme.paper.ignoresSafeArea())
            .navigationTitle(Text(verbatim: "صفحة " + String(m.readerPage) + " · " + String(m.readerPage - m.readerRange.lowerBound + 1) + " من " + String(m.readerRange.count)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)) }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { m.fontSize = max(18, m.fontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                    Button { m.fontSize = min(44, m.fontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                }
                ToolbarItem(placement: .bottomBar) {
                    if m.readerPage == m.readerRange.upperBound {
                        Button { m.markDone(); dismiss() } label: { Text(verbatim: "خلصت الورد ✓").bold() }
                    }
                }
            }
        }
        .tint(KhTheme.accent)
        .khRTL()
    }
}

struct KhPageView: View {
    let page: Int
    let fontSize: Double

    private struct Seg: Identifiable {
        let id: Int
        let surah: Int
        let header: Bool
        let text: String
        var basmala: String? = nil
    }

    private var segs: [Seg] {
        let q = KhQuran.shared
        var out: [Seg] = []
        var cur = ""
        var curS = 0
        for (s, a) in KhQuran.ayahs(onPage: page) {
            if s != curS || a == 1 {
                if !cur.isEmpty { out.append(Seg(id: out.count, surah: curS, header: false, text: cur)); cur = "" }
                curS = s
                if a == 1 { out.append(Seg(id: out.count, surah: s, header: true, text: "", basmala: q.split(s, a).basmala)) }
            }
            cur += (cur.isEmpty ? "" : " ") + q.split(s, a).rest + " " + KhQuran.marker(a)
        }
        if !cur.isEmpty { out.append(Seg(id: out.count, surah: curS, header: false, text: cur)) }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text(verbatim: "سورة " + KhQuran.suras[KhQuran.pages[page - 1].0 - 1].name)
                    Spacer()
                    Text(verbatim: String(page))
                }
                .font(.caption.weight(.semibold)).foregroundColor(KhTheme.gold)
                ForEach(segs) { g in
                    if g.header {
                        VStack(spacing: 10) {
                            Text(verbatim: "سورة " + KhQuran.suras[g.surah - 1].name)
                                .font(.headline).foregroundColor(KhTheme.accent)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KhTheme.soft))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(KhTheme.gold.opacity(0.6), lineWidth: 1))
                            if let b = g.basmala {
                                Text(verbatim: b).font(KhFont.quran(fontSize)).foregroundColor(.primary)
                            }
                        }
                    } else {
                        Text(verbatim: g.text)
                            .font(KhFont.quran(fontSize))
                            .lineSpacing(fontSize * 0.55)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 18).padding(.top, 10)
        }
    }
}
