import Foundation

enum Days {
    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()
    private static let isoFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static var today: Date { cal.startOfDay(for: Date()) }
    static func dayOf(_ d: Date) -> Date { cal.startOfDay(for: d) }
    static func add(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d) ?? d }
    static func iso(_ d: Date) -> String { isoFmt.string(from: d) }
    static func parse(_ s: String) -> Date? { isoFmt.date(from: s) }
    /// 1 = Monday ... 7 = Sunday (ISO, like java.time)
    static func isoWeekday(_ d: Date) -> Int { let w = cal.component(.weekday, from: d); return w == 1 ? 7 : w - 1 }
    static func dayOfMonth(_ d: Date) -> Int { cal.component(.day, from: d) }
}

struct StudentStats {
    var memorisedAyat: Int
    var memorisedPages: Double
    var juzEquivalent: Double
    var goalProgress: Double
    var recordsLast30: Int
    var hifzAyatLast30: Int
    var murajaAyatLast30: Int
    var averageGrade: Double
    var attendanceRate: Double
    var presentDays: Int
    var absentDays: Int
    var points: Int
    var streakDays: Int
    var lastRecord: Recitation?
    /// Ayat recorded per day for the last 14 days, oldest first.
    var dailyAyat: [(Date, Int)]
}

struct CenterStats {
    var students: Int
    var circles: Int
    var teachers: Int
    var recordsToday: Int
    var attendanceToday: Double
    var ayatThisWeek: Int
    var gradeDistribution: [Grade: Int]
    var dailyRecords: [(Date, Int)]
    var kindSplit: [RecordKind: Int]
}

enum Stats {
    static func ayatOf(_ r: Recitation) -> Int { Quran.ayatBetween(r.fromSurah, r.fromAyah, r.toSurah, r.toAyah) }

    static func pagesOf(_ r: Recitation) -> Double {
        guard Quran.isValid(r.fromSurah, r.fromAyah), Quran.isValid(r.toSurah, r.toAyah) else { return 0 }
        return Quran.pagesOf(Quran.globalIndex(r.fromSurah, r.fromAyah), Quran.globalIndex(r.toSurah, r.toAyah))
    }

    static func memorisedMask(_ records: [Recitation]) -> [Bool] {
        var mask = [Bool](repeating: false, count: Quran.totalAyat + 1)
        for r in records where r.kind == .hifz && r.grade != .weak {
            if Quran.isValid(r.fromSurah, r.fromAyah) && Quran.isValid(r.toSurah, r.toAyah) {
                let a = Quran.globalIndex(r.fromSurah, r.fromAyah), b = Quran.globalIndex(r.toSurah, r.toAyah)
                if a <= b { for i in a...b { mask[i] = true } }
            }
        }
        return mask
    }

    static func forStudent(_ student: Student, _ snap: CenterSnapshot, today: Date = Days.today) -> StudentStats {
        let recs = snap.recitations.filter { $0.studentId == student.id }.sorted { $0.recordedAt > $1.recordedAt }
        let mask = memorisedMask(recs)
        let ayat = mask.dropFirst().filter { $0 }.count
        let pages = Quran.pagesForMask(mask)
        let juz = Quran.juzEquivalent(pages)
        let since = Days.add(today, -29)
        let last30 = recs.filter { Days.dayOf($0.recordedAt) >= since }
        let att = snap.attendance.filter { $0.studentId == student.id }
        let present = att.filter { $0.status.isPresent }.count
        let absent = att.filter { $0.status == .absent }.count
        let counted = att.filter { $0.status != .excused }.count
        let points = snap.rewards.filter { $0.studentId == student.id }.reduce(0) { $0 + $1.points }
        let days = Set(recs.map { Days.dayOf($0.recordedAt) })
        var streak = 0
        var d = days.contains(today) ? today : Days.add(today, -1)
        while days.contains(d) { streak += 1; d = Days.add(d, -1) }
        let daily: [(Date, Int)] = (0...13).reversed().map { back in
            let day = Days.add(today, -back)
            return (day, recs.filter { Days.dayOf($0.recordedAt) == day }.reduce(0) { $0 + ayatOf($1) })
        }
        let avg = recs.isEmpty ? 0 : Double(recs.reduce(0) { $0 + $1.grade.score }) / Double(recs.count)
        return StudentStats(
            memorisedAyat: ayat,
            memorisedPages: pages,
            juzEquivalent: juz,
            goalProgress: student.goalJuz > 0 ? min(max(juz / Double(student.goalJuz), 0), 1) : 0,
            recordsLast30: last30.count,
            hifzAyatLast30: last30.filter { $0.kind == .hifz }.reduce(0) { $0 + ayatOf($1) },
            murajaAyatLast30: last30.filter { $0.kind != .hifz }.reduce(0) { $0 + ayatOf($1) },
            averageGrade: avg,
            attendanceRate: counted == 0 ? 0 : Double(present) / Double(counted),
            presentDays: present,
            absentDays: absent,
            points: points,
            streakDays: streak,
            lastRecord: recs.first,
            dailyAyat: daily
        )
    }

    static func forCenter(_ snap: CenterSnapshot, _ students: [Student], today: Date = Days.today) -> CenterStats {
        let ids = Set(students.map { $0.id })
        let recs = snap.recitations.filter { ids.contains($0.studentId) }
        let todayIso = Days.iso(today)
        let attToday = snap.attendance.filter { ids.contains($0.studentId) && $0.day == todayIso }
        let presentToday = attToday.filter { $0.status.isPresent }.count
        let weekStart = Days.add(today, -6)
        var gd: [Grade: Int] = [:]
        for g in Grade.allCases { gd[g] = recs.filter { $0.grade == g }.count }
        var ks: [RecordKind: Int] = [:]
        for k in RecordKind.allCases { ks[k] = recs.filter { $0.kind == k }.reduce(0) { $0 + ayatOf($1) } }
        return CenterStats(
            students: students.count,
            circles: snap.circles.filter { c in students.contains { $0.circleId == c.id } }.count,
            teachers: snap.teachers().count,
            recordsToday: recs.filter { Days.dayOf($0.recordedAt) == today }.count,
            attendanceToday: attToday.isEmpty ? 0 : Double(presentToday) / Double(attToday.count),
            ayatThisWeek: recs.filter { Days.dayOf($0.recordedAt) >= weekStart }.reduce(0) { $0 + ayatOf($1) },
            gradeDistribution: gd,
            dailyRecords: (0...13).reversed().map { back in
                let day = Days.add(today, -back)
                return (day, recs.filter { Days.dayOf($0.recordedAt) == day }.count)
            },
            kindSplit: ks
        )
    }

    static func describeRange(_ r: Recitation) -> String {
        r.fromSurah == r.toSurah
            ? "\(Quran.name(r.fromSurah)) \(r.fromAyah)–\(r.toAyah)"
            : "\(Quran.name(r.fromSurah)) \(r.fromAyah) إلى \(Quran.name(r.toSurah)) \(r.toAyah)"
    }
}
