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
    var passwordHashes: [String: String]
    var currentUserId: String?
    var seedVersion: Int
}

/// Sample data for design and testing only. Never used once the central database is connected.
enum DemoSeed {
    static let version = 3
    static let demoPassword = "123456"
    static let adminPhone = "0500000001"
    static let teacherPhone = "0500000002"
    static let studentPhone = "0500000010"
    static let parentPhone = "0500000020"

    static func create() -> DemoStore {
        var rnd = SeededRandom(7)
        let today = Days.today
        let day = 86_400.0

        let admin = Member(id: "m-admin", fullName: "إدارة المركز", phone: adminPhone, role: .admin)
        let t1 = Member(id: "m-t1", fullName: "الشيخ عبدالله الحربي", phone: teacherPhone, role: .teacher)
        let t2 = Member(id: "m-t2", fullName: "الأستاذ خالد العمري", phone: "0500000003", role: .teacher)
        let t3 = Member(id: "m-t3", fullName: "الأستاذ ياسر القحطاني", phone: "0500000004", role: .teacher)

        let circles = [
            StudyCircle(id: "c1", name: "حلقة أبي بكر الصديق", teacherId: t1.id, level: "متقدم", schedule: "بعد العصر • السبت–الأربعاء", capacity: 15),
            StudyCircle(id: "c2", name: "حلقة عمر بن الخطاب", teacherId: t2.id, level: "متوسط", schedule: "بعد العصر • السبت–الأربعاء", capacity: 15),
            StudyCircle(id: "c3", name: "حلقة البراعم", teacherId: t3.id, level: "تمهيدي", schedule: "بعد المغرب • الأحد–الخميس", capacity: 20),
            StudyCircle(id: "c4", name: "حلقة الفجر للكبار", teacherId: t1.id, level: "مراجعة", schedule: "بعد الفجر • يومياً", capacity: 12)
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
        let studentUser = Member(id: "m-s1", fullName: students[0].fullName, phone: studentPhone, role: .student, studentId: students[0].id)
        let p1 = Member(id: "m-p1", fullName: "والد محمد السالمي", phone: parentPhone, role: .parent, childIds: ["s1", "s5"])
        let p2 = Member(id: "m-p2", fullName: "والد أحمد الزهراني", phone: "0500000021", role: .parent, childIds: ["s2"])
        let p3 = Member(id: "m-p3", fullName: "والدة يوسف الغامدي", phone: "0500000022", role: .parent, childIds: ["s4", "s8"])
        let members = [admin, t1, t2, t3, studentUser, p1, p2, p3]

        var recs: [Recitation] = []
        var att: [Attendance] = []
        var rewards: [Reward] = []
        var seq = 0
        let gradeTable = [0, 0, 0, 1, 1, 1, 2, 2, 3, 4]
        let grades = Grade.allCases
        for (idx, s) in students.enumerated() {
            let circle = circles.first { $0.id == s.circleId }!
            let teacher = circle.teacherId ?? admin.id
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
                                       mistakes: rnd.int(4), notes: "", recordedAt: at)); seq += 1
                if rnd.int(3) == 0 {
                    recs.append(Recitation(id: "r\(seq)", studentId: s.id, circleId: circle.id, teacherId: teacher, kind: .muraja,
                                           fromSurah: surah, fromAyah: 1, toSurah: surah, toAyah: toAyah, grade: grades[rnd.int(3)],
                                           mistakes: rnd.int(3), notes: "", recordedAt: at.addingTimeInterval(600))); seq += 1
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
            Announcement(id: "n1", title: "مسابقة الحفظ الشهرية", body: "تبدأ مسابقة المركز الشهرية يوم الخميس القادم بعد العصر، والجوائز للمراكز الثلاثة الأولى في كل حلقة.", audience: .all, createdBy: admin.id, createdAt: now.addingTimeInterval(-2 * day)),
            Announcement(id: "n2", title: "اجتماع أولياء الأمور", body: "نتشرف بحضوركم لقاء أولياء الأمور يوم السبت بعد المغرب في مصلى المركز.", audience: .parents, createdBy: admin.id, createdAt: now.addingTimeInterval(-4 * day)),
            Announcement(id: "n3", title: "تحديث خطة المراجعة", body: "اعتماد مراجعة جزء كامل أسبوعياً لطلاب الحلقات المتقدمة.", audience: .teachers, createdBy: admin.id, createdAt: now.addingTimeInterval(-6 * day))
        ]
        let notes = [
            AppNotification(id: "x1", userId: p1.id, title: "حفظ جديد: محمد السالمي", body: "سورة البقرة • ممتاز", kind: "record", createdAt: now.addingTimeInterval(-3600)),
            AppNotification(id: "x2", userId: p1.id, title: "إعلان: اجتماع أولياء الأمور", body: "نتشرف بحضوركم لقاء أولياء الأمور يوم السبت بعد المغرب.", kind: "announcement", refId: "n2", createdAt: now.addingTimeInterval(-4 * day)),
            AppNotification(id: "x3", userId: studentUser.id, title: "مكافأة 🎉", body: "+15 نقطة: إتقان الحفظ هذا الأسبوع", kind: "reward", createdAt: now.addingTimeInterval(-day)),
            AppNotification(id: "x4", userId: t1.id, title: "إعلان: تحديث خطة المراجعة", body: "اعتماد مراجعة جزء كامل أسبوعياً.", kind: "announcement", refId: "n3", read: true, createdAt: now.addingTimeInterval(-6 * day)),
            AppNotification(id: "x5", userId: admin.id, title: "مرحباً بك في مركز الصديق", body: "هذه نسخة تجريبية ببيانات نموذجية. ستُربط بقاعدة البيانات المركزية قريباً.", kind: "info", createdAt: now)
        ]
        let data = CenterSnapshot(center: CenterInfo(), members: members, circles: circles, students: students,
                                  recitations: recs, attendance: att, rewards: rewards,
                                  announcements: announcements, notifications: notes)
        var hashes: [String: String] = [:]
        for m in members { hashes[m.id] = sha256(demoPassword) }
        return DemoStore(data: data, passwordHashes: hashes, currentUserId: nil, seedVersion: version)
    }
}
