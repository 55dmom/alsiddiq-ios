import SwiftUI

enum AdkSection: Int, CaseIterable, Identifiable {
    case sabah, masa, salah, nawm
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .sabah: return "الصباح"
        case .masa: return "المساء"
        case .salah: return "بعد الصلاة"
        case .nawm: return "النوم"
        }
    }
    var hint: String {
        switch self {
        case .sabah: return "من بعد الفجر إلى طلوع الشمس"
        case .masa: return "من بعد العصر إلى غروب الشمس"
        case .salah: return "بعد السلام من الصلاة المفروضة"
        case .nawm: return "عند الاضطجاع للنوم"
        }
    }
    var items: [AdkItem] {
        switch self {
        case .sabah: return AdhkarData.sabah
        case .masa: return AdhkarData.masa
        case .salah: return AdhkarData.salah
        case .nawm: return AdhkarData.nawm
        }
    }
    /// A sensible default for the time of day.
    static var now: AdkSection {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 3 && h < 12 { return .sabah }
        if h >= 15 && h < 21 { return .masa }
        if h >= 21 || h < 3 { return .nawm }
        return .salah
    }
}

/// Small drawn glyphs (no stars).
struct AdkGlyph: View {
    let section: AdkSection
    var body: some View {
        switch section {
        case .sabah:
            ZStack {
                Circle().trim(from: 0.5, to: 1).fill(Color.white).frame(width: 30, height: 30).offset(y: 6)
                Capsule().fill(Color.white).frame(width: 40, height: 3).offset(y: 7)
                Capsule().fill(Color.white.opacity(0.7)).frame(width: 26, height: 3).offset(y: 14)
            }
        case .masa:
            Image(systemName: "moon.fill").font(.system(size: 28, weight: .semibold)).foregroundColor(.white)
        case .salah:
            VStack(spacing: 0) {
                Circle().trim(from: 0.5, to: 1).fill(Color.white).frame(width: 26, height: 26).offset(y: 13)
                RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 34, height: 14)
            }
        case .nawm:
            Image(systemName: "moon.zzz.fill").font(.system(size: 28, weight: .semibold)).foregroundColor(.white)
        }
    }
}

/// Progress for today, saved in UserDefaults ("alsalmi.adhkar.*"); a new day starts fresh.
final class AdkModel: ObservableObject {
    private let d = UserDefaults.standard
    private let k = "alsalmi.adhkar."
    @Published var section: AdkSection = AdkSection.now
    @Published var done: [String: Int] = [:]
    @Published var openSource: Set<String> = []
    @Published var bump: String = ""
    @Published var confirmReset = false
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: k + "font") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: k + "haptics") } }

    private var day: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    init() {
        let fs = d.double(forKey: k + "font")
        fontSize = fs > 0 ? fs : 21
        haptics = d.object(forKey: k + "haptics") as? Bool ?? true
        load()
    }

    func load() {
        if d.string(forKey: k + "day") == day, let saved = d.dictionary(forKey: k + "done") as? [String: Int] {
            done = saved
        } else {
            done = [:]
            save()
        }
    }

    private func save() {
        d.set(day, forKey: k + "day")
        d.set(done, forKey: k + "done")
    }

    func count(_ x: AdkItem) -> Int { min(done[x.id] ?? 0, x.count) }
    func finished(_ x: AdkItem) -> Bool { count(x) >= x.count }

    /// Returns true when this item has just been completed.
    @discardableResult
    func tap(_ x: AdkItem) -> Bool {
        if d.string(forKey: k + "day") != day { done = [:] }
        let c = count(x)
        if c >= x.count { return false }
        done[x.id] = c + 1
        bump = x.id + "#" + String(c + 1)
        save()
        return c + 1 >= x.count
    }

    func reset(_ s: AdkSection) {
        for x in s.items { done[x.id] = nil }
        save()
    }

    func toggleSource(_ id: String) {
        if openSource.contains(id) { openSource.remove(id) } else { openSource.insert(id) }
    }

    func progress(_ s: AdkSection) -> (Int, Int) {
        let items = s.items
        return (items.filter { finished($0) }.count, items.count)
    }
    func nextOpen(_ s: AdkSection) -> AdkItem? { s.items.first { !finished($0) } }
}

/// «الأذكار» — the button's single entry view.
public struct AdhkarView: View {
    @StateObject private var m = AdkModel()

    public init() {}

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    hero.id("top")
                    chips
                    if m.progress(m.section).0 == m.progress(m.section).1 { doneCard.transition(.scale.combined(with: .opacity)) }
                    ForEach(Array(m.section.items.enumerated()), id: \.element.id) { i, x in
                        card(x, index: i + 1).id(x.id)
                    }
                    Button { m.confirmReset = true } label: {
                        Label { Text(verbatim: "إعادة أذكار " + m.section.title) } icon: { Image(systemName: "arrow.counterclockwise") }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(Capsule().fill(AdkTheme.soft))
                    }
                    .buttonStyle(AdkPress())
                    .padding(.vertical, 10)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: m.done)
            }
            .onChange(of: m.section) { _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            .onChange(of: m.bump) { _ in
                // after finishing one, glide to the next open item
                if let n = m.nextOpen(m.section), let cur = m.section.items.first(where: { m.bump.hasPrefix($0.id + "#") }), m.finished(cur) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(n.id, anchor: .top) } }
                }
            }
        }
        .background(AdkTheme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "الأذكار"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { m.fontSize = max(16, m.fontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                    .accessibilityLabel(Text(verbatim: "تصغير الخط"))
                Button { m.fontSize = min(36, m.fontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                    .accessibilityLabel(Text(verbatim: "تكبير الخط"))
                Button { m.haptics.toggle() } label: { Image(systemName: m.haptics ? "iphone.radiowaves.left.and.right" : "iphone.slash") }
                    .accessibilityLabel(Text(verbatim: "الاهتزاز"))
            }
        }
        .alert(Text(verbatim: "إعادة العدّ؟"), isPresented: $m.confirmReset) {
            Button(role: .destructive) { withAnimation { m.reset(m.section) } } label: { Text(verbatim: "إعادة") }
            Button(role: .cancel) {} label: { Text(verbatim: "إلغاء") }
        } message: { Text(verbatim: "يرجع عدّاد أذكار " + m.section.title + " إلى الصفر.") }
        .onAppear { m.load() }
        .tint(AdkTheme.accent)
        .adkRTL()
    }

    private var hero: some View {
        let p = m.progress(m.section)
        let frac = Double(p.0) / Double(max(p.1, 1))
        return AdkHero(title: "أذكار " + m.section.title, subtitle: m.section.hint + "\n" + String(p.0) + " من " + String(p.1) + " مكتملة") {
            AdkRing(progress: frac, size: 74, line: 7) {
                AdkGlyph(section: m.section)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AdkSection.allCases) { s in
                    let p = m.progress(s)
                    AdkChip(title: s.title + (p.0 == p.1 ? " ✓" : ""), selected: m.section == s) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { m.section = s }
                    }
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 4)
        }
    }

    private var doneCard: some View {
        AdkCard {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundColor(AdkTheme.good)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "أتممت أذكار " + m.section.title).font(.headline)
                    Text(verbatim: "تقبّل الله منك، وجعلها في ميزان حسناتك").font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
    }

    private func card(_ x: AdkItem, index: Int) -> some View {
        let c = m.count(x)
        let fin = m.finished(x)
        let open = m.openSource.contains(x.id)
        return AdkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(verbatim: String(index))
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(fin ? AdkTheme.good.opacity(0.15) : AdkTheme.soft))
                        .foregroundColor(fin ? AdkTheme.good : AdkTheme.accent)
                    if x.quran {
                        Text(verbatim: "قرآن").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(AdkTheme.gold.opacity(0.15)))
                            .foregroundColor(AdkTheme.gold)
                    }
                    Text(verbatim: x.count > 1 ? "يُكرَّر " + String(x.count) + " مرات" : "مرة واحدة")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    if fin {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(AdkTheme.good)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    if x.basmala {
                        Text(verbatim: AdhkarData.basmala)
                            .font(AdkFont.quran(m.fontSize))
                            .frame(maxWidth: .infinity)
                    }
                    Text(verbatim: x.text)
                        .font(x.quran ? AdkFont.quran(m.fontSize + 1) : .system(size: m.fontSize))
                        .lineSpacing(x.quran ? 12 : 8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture { tap(x) }

                if !x.reward.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(AdkTheme.gold).frame(width: 3)
                        Text(verbatim: x.reward).font(.footnote).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { m.toggleSource(x.id) } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: open ? "chevron.up" : "book.closed")
                            Text(verbatim: x.ref).lineLimit(1)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundColor(AdkTheme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(AdkTheme.soft))
                    }
                    .buttonStyle(AdkPress())
                    Spacer()
                    Button { tap(x) } label: {
                        AdkRing(progress: Double(c) / Double(max(x.count, 1)), size: 58, line: 5, onGradient: false) {
                            if fin {
                                Image(systemName: "checkmark").font(.system(size: 20, weight: .bold)).foregroundColor(AdkTheme.good)
                            } else {
                                VStack(spacing: 0) {
                                    Text(verbatim: String(c)).font(.system(size: 19, weight: .bold, design: .rounded))
                                        .contentTransition(.numericText())
                                    Text(verbatim: "من " + String(x.count)).font(.system(size: 9)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(AdkPress())
                    .disabled(fin)
                    .accessibilityLabel(Text(verbatim: "عدّ"))
                }

                if open {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "التخريج: " + x.source)
                        Text(verbatim: "الحكم: " + x.grade)
                        if !x.note.isEmpty { Text(verbatim: "ملاحظة: " + x.note) }
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AdkTheme.soft))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(fin ? AdkTheme.good.opacity(0.5) : Color.clear, lineWidth: 1.2))
        .opacity(fin ? 0.72 : 1)
        .scaleEffect(m.bump.hasPrefix(x.id + "#") && !fin ? 1.0 : 1.0)
    }

    private func tap(_ x: AdkItem) {
        if m.finished(x) { return }
        let completed = withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { m.tap(x) }
        if m.haptics { completed ? AdkHaptics.success() : AdkHaptics.tap() }
    }
}
