import Foundation

struct TsbPhrase: Identifiable, Equatable {
    let id: Int
    let text: String
    let ref: String
}

/// Counter state, saved in UserDefaults under "alsalmi.tasbeeh.*".
final class TasbeehModel: ObservableObject {
    static let phrases: [TsbPhrase] = [
        TsbPhrase(id: 0, text: "سُبْحَانَ اللَّهِ", ref: "مسلم 597"),
        TsbPhrase(id: 1, text: "الْحَمْدُ لِلَّهِ", ref: "مسلم 597"),
        TsbPhrase(id: 2, text: "اللَّهُ أَكْبَرُ", ref: "مسلم 597"),
        TsbPhrase(id: 3, text: "لاَ إِلَهَ إِلاَّ اللَّهُ", ref: "مسلم 2137"),
        TsbPhrase(id: 4, text: "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", ref: "مسلم 2692"),
        TsbPhrase(id: 5, text: "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ، سُبْحانَ اللَّهِ الْعَظِيمِ", ref: "البخاري 6682، ومسلم 2694"),
        TsbPhrase(id: 6, text: "أَسْتَغْفِرُ اللَّهَ وَأَتُوبُ إِلَيْهِ", ref: "صحيح الجامع 944"),
        TsbPhrase(id: 7, text: "لاَ حَوْلَ وَلاَ قُوَّةَ إِلاَّ بِاللَّهِ", ref: "البخاري 6384، ومسلم 2704"),
        TsbPhrase(id: 8, text: "لاَ إِلَهَ إِلاَّ اللَّهُ وَحْدَهُ لاَ شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ", ref: "البخاري 6403، ومسلم 2691")
    ]
    static let presetTargets = [33, 99, 100]

    private let d = UserDefaults.standard
    private let k = "alsalmi.tasbeeh."

    @Published var selected: Int { didSet { d.set(selected, forKey: k + "sel") } }
    @Published var counts: [Int] { didSet { d.set(counts, forKey: k + "counts") } }
    @Published var target: Int { didSet { d.set(target, forKey: k + "target") } }
    @Published var rounds: Int { didSet { d.set(rounds, forKey: k + "rounds") } }
    @Published var total: Int { didSet { d.set(total, forKey: k + "total") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: k + "haptics") } }
    @Published var customOpen = false
    @Published var customText = ""
    @Published var resetOpen = false

    init() {
        let n = TasbeehModel.phrases.count
        selected = min(max(d.integer(forKey: k + "sel"), 0), n - 1)
        var c = (d.array(forKey: k + "counts") as? [Int]) ?? []
        if c.count != n { c = Array(repeating: 0, count: n) }
        counts = c
        let t = d.integer(forKey: k + "target")
        target = t > 0 ? t : 33
        rounds = d.integer(forKey: k + "rounds")
        total = d.integer(forKey: k + "total")
        haptics = d.object(forKey: k + "haptics") as? Bool ?? true
    }

    var phrase: TsbPhrase { TasbeehModel.phrases[selected] }
    var count: Int { counts[selected] }
    var progress: Double { target > 0 ? min(Double(count) / Double(target), 1) : 0 }
    var isCustomTarget: Bool { !TasbeehModel.presetTargets.contains(target) }

    /// One tap. Returns true when the target was just reached (the count starts a new round).
    @discardableResult
    func tap() -> Bool {
        var c = counts
        c[selected] += 1
        total += 1
        if target > 0 && c[selected] >= target {
            c[selected] = 0
            counts = c
            rounds += 1
            return true
        }
        counts = c
        return false
    }

    func select(_ i: Int) { selected = i }

    func resetCurrent() {
        var c = counts
        c[selected] = 0
        counts = c
        rounds = 0
    }

    func resetAll() {
        counts = Array(repeating: 0, count: TasbeehModel.phrases.count)
        rounds = 0
        total = 0
    }

    func applyCustom() {
        let digits = customText.filter { $0.isNumber }
        let latin = String(digits.map { ch -> Character in
            if let v = ch.wholeNumberValue { return Character(String(v)) }
            return ch
        })
        if let v = Int(latin), v > 0, v <= 100000 { target = v }
        customText = ""
    }
}
