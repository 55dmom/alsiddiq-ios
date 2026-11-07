import Foundation

enum Fmt {
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
