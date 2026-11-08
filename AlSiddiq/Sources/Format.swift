import Foundation

enum Fmt {
    /// Student counts with correct Arabic plurals (his rule): 0 «لا طلاب»، 1 «طالب واحد»، 2 «طالبان»، 3–10 «N طلاب»، 11+ «N طالب».
    static func students(_ n: Int) -> String {
        switch n {
        case ..<1: return "لا طلاب"
        case 1: return "طالب واحد"
        case 2: return "طالبان"
        case 3...10: return "\(n) طلاب"
        default: return "\(n) طالب"
        }
    }
    static let feePeriods: [(String, String)] = [("monthly", "شهرياً"), ("term", "للفصل"), ("once", "مرة واحدة")]
    private static let arNumber: NumberFormatter = {
        let f = NumberFormatter(); f.locale = Locale(identifier: "ar@numbers=arab"); f.numberStyle = .decimal; f.usesGroupingSeparator = true; return f
    }()
    /// «الرسوم: ٥٬٠٠٠ ريال يمني شهرياً»; nil when the circle has no fee.
    static func fee(_ c: StudyCircle) -> String? {
        guard let v = c.feeYer else { return nil }
        if v == 0 { return "الرسوم: مجاناً" }
        let n = arNumber.string(from: NSNumber(value: v)) ?? "\(v)"
        let p = feePeriods.first { $0.0 == c.feePeriod }?.1
        return "الرسوم: \(n) ريال يمني" + (p.map { " " + $0 } ?? "")
    }
    /// Circle level as shown: the old «تمهيدي» is shown as «مبتدئ» (a stored value is never rewritten by this).
    static func level(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) == "تمهيدي" ? "مبتدئ" : s }
    private static let ar = Locale(identifier: "ar@numbers=latn")
    private static func fmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = ar
        f.timeZone = TimeZone.current
        f.dateFormat = pattern
        return f
    }
    private static let time = fmt("h:mm a")
    private static let dateF = fmt("d MMMM yyyy")
    private static let dayMonth = fmt("EEEE d MMMM")
    private static let hijriMonths = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة",
                                      "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]

    static func relative(_ d: Date) -> String {
        let days = Days.cal.dateComponents([.day], from: Days.dayOf(d), to: Days.today).day ?? 0
        switch days {
        case 0: return "اليوم \(time.string(from: d))"
        case 1: return "أمس \(time.string(from: d))"
        case 2..<7: return "قبل \(days) أيام"
        default: return dateF.string(from: d)
        }
    }
    static func date(_ d: Date) -> String { dateF.string(from: d) }
    static func dayTitle(_ d: Date) -> String { dayMonth.string(from: d) }
    static func hijri(_ d: Date = Date()) -> String {
        let cal = Calendar(identifier: .islamicUmmAlQura)
        let c = cal.dateComponents([.day, .month, .year], from: d)
        guard let day = c.day, let m = c.month, let y = c.year, (1...12).contains(m) else { return "" }
        return "\(day) \(hijriMonths[m - 1]) \(y)هـ"
    }
    static func one(_ x: Double) -> String {
        if x >= 10 || x == x.rounded(.down) { return String(Int(x)) }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), x)
    }
    static func pct(_ x: Double) -> String { "\(Int(x * 100))%" }

    static func shortDay(_ d: Date) -> String {
        switch Days.isoWeekday(d) {
        case 6: return "سبت"; case 7: return "أحد"; case 1: return "إثنين"; case 2: return "ثلاثاء"
        case 3: return "أربعاء"; case 4: return "خميس"; default: return "جمعة"
        }
    }
}
