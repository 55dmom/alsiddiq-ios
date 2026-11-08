import Foundation
import CryptoKit

/// Deterministic random numbers (SplitMix64) so the sample data is stable between launches.
struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func bool() -> Bool { next() & 1 == 1 }
    mutating func int(in r: ClosedRange<Int>) -> Int { r.lowerBound + int(r.upperBound - r.lowerBound + 1) }
}

func sha256(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

struct DemoStore: Codable {
    var data: CenterSnapshot
    /// account id -> sha256 of its password (viewer, admin, teachers).
    var passwordHashes: [String: String]
    var currentUserId: String?
    var baseUserId: String? = nil
    var photos: [String: Data] = [:]
    var seedVersion: Int
}

/// Sample data for design and testing only. Never used once the central database is connected.
enum DemoSeed {
    static let version = 6
    /// Demo passwords (sample data only): general view, admin, and each teacher's own (v3.3).
    static let viewerPassword = "111111"
    static let adminPassword = "222222"
    static let teacherPassword = "333333"   // الشيخ عبدالله الحربي (حلقة أبي بكر + حلقة الفجر)
    static let teacher2Password = "444444"  // الأستاذ خالد العمري (حلقة عمر)
    static let teacher3Password = "555555"  // الأستاذ ياسر القحطاني (حلقة البراعم)

    static func create() -> DemoStore {
        var rnd = SeededRandom(7)
        let today = Days.today
        let day = 86_400.0

        let admin = Member(id: "m-admin", fullName: "الإدارة", role: .admin)
        let viewer = Member(id: "m-viewer", fullName: "عرض عام", role: .viewer)
        // v3.3: each teacher is his own account with his own password and circle.
        let m1 = Member(id: "m-t1", fullName: "الشيخ عبدالله الحربي", role: .teacher)
        let m2 = Member(id: "m-t2", fullName: "الأستاذ خالد العمري", role: .teacher)
        let m3 = Member(id: "m-t3", fullName: "الأستاذ ياسر القحطاني", role: .teacher)
        let t1 = TeacherName(id: m1.id, name: m1.fullName)
        let t2 = TeacherName(id: m2.id, name: m2.fullName)
        let t3 = TeacherName(id: m3.id, name: m3.fullName)

        let circles = [
            StudyCircle(id: "c1", name: "حلقة أبي بكر الصديق", teacherId: "m-t1", teacherName: t1.name, feeYer: 5000, feePeriod: "monthly", level: "متقدم", schedule: "بعد العصر • السبت–الأربعاء", capacity: 15),
            StudyCircle(id: "c2", name: "حلقة عمر بن الخطاب", teacherId: "m-t2", teacherName: t2.name, level: "متوسط", schedule: "بعد العصر • السبت–الأربعاء", capacity: 15),
            StudyCircle(id: "c3", name: "حلقة البراعم", teacherId: "m-t3", teacherName: t3.name, feeYer: 15000, feePeriod: "term", level: "مبتدئ", schedule: "بعد المغرب • الأحد–الخميس", capacity: 20),
            StudyCircle(id: "c4", name: "حلقة الفجر للكبار", teacherId: "m-t1", teacherName: t1.name, level: "مراجعة", schedule: "بعد الفجر • يومياً", capacity: 12)
        ]
        let names = [
            "محمد السالمي", "أحمد الزهراني", "عبدالرحمن الشهري", "يوسف الغامدي", "عمر الدوسري",
            "إبراهيم المالكي", "سلمان العتيبي", "فيصل الشمري", "حمزة البقمي", "أنس الحارثي",
            "زياد القرني", "معاذ السبيعي", "بلال المطيري", "عبدالعزيز الجهني", "مالك الرشيدي",
            "سعد الأحمدي", "تركي العنزي", "نواف الخالدي"
        ]
        let students: [Student] = names.enumerated().map { i, n in
            let circle = circles[i % circles.count]
            return Student(
                id: "s\(i + 1)", fullName: n, phone: String(format: "05000001%02d", i),
                birthYear: 2008 + (i % 9), circleId: circle.id,
                joinedOn: Days.iso(Days.add(today, -(40 + i * 9))),
                goalJuz: circle.id == "c3" ? 3 : (circle.id == "c4" ? 30 : 10)
            )
        }
        let members = [admin, viewer, m1, m2, m3]
        let tnames = [t1, t2, t3]

        var recs: [Recitation] = []
        var att: [Attendance] = []
        var rewards: [Reward] = []
        var seq = 0
        let gradeTable = [0, 0, 0, 1, 1, 1, 2, 2, 3, 4]
        let grades = Grade.allCases
        for (idx, s) in students.enumerated() {
            let circle = circles.first { $0.id == s.circleId }!
            let teacher = circle.teacherId ?? m1.id
            let byName = circle.teacherName ?? ""
            var surah = circle.id == "c3" ? 114 : (circle.id == "c4" ? 2 : 1 + (idx % 3))
            var ayah = 1
            for back in (0...20).reversed() {
                let d = Days.add(today, -back)
                if Days.isoWeekday(d) == 5 { continue } // Friday off
                let present = rnd.int(100) < 88
                let status: AttendanceStatus = present ? (rnd.int(10) == 0 ? .late : .present) : (rnd.bool() ? .excused : .absent)
                att.append(Attendance(id: "a\(seq)", studentId: s.id, circleId: circle.id, day: Days.iso(d), status: status, recordedBy: teacher)); seq += 1
                if !present { continue }
                let at = d.addingTimeInterval(Double((16 + rnd.int(3)) * 3600 + rnd.int(60) * 60))
                let count = (circle.id == "c3" ? 2 : 4) + rnd.int(5)
                let toAyah = min(ayah + count - 1, Quran.ayahCount(surah))
                let grade = grades[gradeTable[rnd.int(10)]]
                recs.append(Recitation(id: "r\(seq)", studentId: s.id, circleId: circle.id, teacherId: teacher, kind: .hifz,
                                       fromSurah: surah, fromAyah: ayah, toSurah: surah, toAyah: toAyah, grade: grade,
                                       mistakes: rnd.int(4), notes: "", recordedAt: at, byName: byName)); seq += 1
                if rnd.int(3) == 0 {
                    recs.append(Recitation(id: "r\(seq)", studentId: s.id, circleId: circle.id, teacherId: teacher, kind: .muraja,
                                           fromSurah: surah, fromAyah: 1, toSurah: surah, toAyah: toAyah, grade: grades[rnd.int(3)],
                                           mistakes: rnd.int(3), notes: "", recordedAt: at.addingTimeInterval(600), byName: byName)); seq += 1
                }
                if grade != .weak {
                    ayah = toAyah + 1
                    if ayah > Quran.ayahCount(surah) {
                        surah = circle.id == "c3" ? max(surah - 1, 78) : min(surah + 1, 114)
                        ayah = 1
                    }
                }
            }
            if idx % 2 == 0 {
                rewards.append(Reward(id: "w\(seq)", studentId: s.id, points: 10 + rnd.int(4) * 5, reason: "إتقان الحفظ هذا الأسبوع", awardedBy: teacher,
                                      createdAt: Date().addingTimeInterval(-Double(rnd.int(in: 1...9)) * day))); seq += 1
            }
            if idx % 3 == 0 {
                rewards.append(Reward(id: "w\(seq)", studentId: s.id, points: 5, reason: "الانضباط في الحضور", awardedBy: teacher,
                                      createdAt: Date().addingTimeInterval(-Double(rnd.int(in: 1...14)) * day))); seq += 1
            }
        }
        let now = Date()
        let announcements = [
            Announcement(id: "n0", title: "تقرير حلقة أبي بكر الصديق — \(Days.iso(today))", body: "حفظ اليوم: 5 طلاب • 38 آية\nالغائبون: أنس الحارثي", audience: .all, createdBy: m1.id, createdAt: now.addingTimeInterval(-3 * 3600)),
            Announcement(id: "n1", title: "مسابقة الحفظ الشهرية", body: "تبدأ مسابقة المركز الشهرية يوم الخميس القادم بعد العصر، والجوائز للمراكز الثلاثة الأولى في كل حلقة.", audience: .all, createdBy: admin.id, createdAt: now.addingTimeInterval(-2 * day)),
            Announcement(id: "n3", title: "تحديث خطة المراجعة", body: "اعتماد مراجعة جزء كامل أسبوعياً لطلاب الحلقات المتقدمة.", audience: .teachers, createdBy: admin.id, createdAt: now.addingTimeInterval(-6 * day))
        ]
        let data = CenterSnapshot(center: CenterInfo(), members: members, circles: circles, students: students,
                                  recitations: recs, attendance: att, rewards: rewards,
                                  announcements: announcements, notifications: [], teacherNames: tnames)
        let hashes = [admin.id: sha256(adminPassword), viewer.id: sha256(viewerPassword), m1.id: sha256(teacherPassword),
                      m2.id: sha256(teacher2Password), m3.id: sha256(teacher3Password)]
        return DemoStore(data: data, passwordHashes: hashes, currentUserId: nil, seedVersion: version)
    }
}
