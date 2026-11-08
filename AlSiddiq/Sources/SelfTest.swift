import SwiftUI
import UIKit

#if DEBUG
/// CI only (Debug builds against the real database, throwaway passwords and rows):
/// logs what this password may see, writes through the app's NORMAL paths, then probes RAW writes
/// past the app's own checks so the log shows the SERVER's own answer. Results go to Documents/selftest.txt.
@MainActor
enum SelfTest {
    static func log(_ s: String) {
        NSLog("ALSIDDIQ_SELFTEST %@", s)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("selftest.txt")
        let line = s + "\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }

    static func ok<T>(_ label: String, _ block: () async throws -> T) async {
        do { _ = try await block(); log("\(label) ok") }
        catch { log("\(label) refused: \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
    }

    static func run(_ model: AppModel, tries: String) async {
        let repo = model.repo
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard let user = repo.currentUser else { log("as=none (sign-in failed)"); log("done"); return }
        try? await repo.refresh()
        let snap = repo.snapshot
        log("as=\(user.role.dbValue) name=\(user.fullName) base=\(repo.baseUser?.role.dbValue ?? "-") sees circles=\(snap.circles.count) students=\(snap.students.count) recs=\(snap.recitations.count) att=\(snap.attendance.count) names=\(snap.teacherNames.count) photos=\(snap.students.filter { $0.photoPath != nil }.count)")
        let pairs: [(String, String)] = tries.split(separator: ",").map { p in
            let a = p.split(separator: ":").map(String.init); return (a.first ?? "", a.count > 1 ? a[1] : "")
        }
        // 1) the app's normal paths, for every student named (in different circles)
        for (sid, cid) in pairs {
            guard var s = repo.snapshot.student(sid) else { log("student \(sid) not visible"); continue }
            let r = Recitation(id: "", studentId: sid, circleId: s.circleId, teacherId: user.id, kind: .hifz, fromSurah: 2, fromAyah: 1, toSurah: 2, toAyah: 5,
                               grade: .excellent, notes: "selftest-app-\(user.role.dbValue)", byName: user.role == .viewer ? "" : "TEST معلم")
            await ok("app logRecitation(\(s.fullName))") { try await repo.logRecitation(r) }
            await ok("app saveAttendance(\(s.fullName))") { try await repo.saveAttendance(circleId: cid, day: Days.iso(Days.today), marks: [sid: .absent]) }
            s.notes = "selftest-app-edit-\(user.role.dbValue)"
            await ok("app saveStudent(\(s.fullName))") { try await repo.saveStudent(s) }
        }
        if let first = pairs.first, user.role != .viewer {
            let sid = first.0
            let img = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { ctx in
                UIColor(red: 0.42, green: 0.16, blue: 0.17, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
                UIColor(red: 0.79, green: 0.64, blue: 0.29, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 150, y: 150, width: 300, height: 300))
            }
            if let data = PhotoTools.jpeg512(img) {
                await ok("app setStudentPhoto(\(sid)) \(data.count)B") { try await repo.setStudentPhoto(studentId: sid, jpeg: data) }
            }
        }
        if user.role == .admin {
            if let np = UserDefaults.standard.string(forKey: "ciNewTeachersPass"), !np.isEmpty {
                await ok("app setAccessPassword(teachers)") { try await repo.setAccessPassword(target: .teacher, password: np) }
            }
            if let c = repo.snapshot.circles.first {
                var c2 = c; c2.schedule = "selftest"
                await ok("app saveCircle(\(c.name))") { try await repo.saveCircle(c2) }
            }
        }
        if user.role != .viewer, let first = pairs.first, let c = repo.snapshot.circle(first.1) {
            let a = Announcement(id: "", title: "TEST تقرير \(c.name) — \(Days.iso(Days.today))", body: CircleReport.body(repo.snapshot, c, Days.today),
                                 audience: .all, createdBy: user.id)
            await ok("app postAnnouncement(report)") { try await repo.postAnnouncement(a) }
        }
        // 2) photo read (any session of the centre)
        try? await repo.refresh()
        if let s = repo.snapshot.students.first(where: { $0.photoPath != nil }) {
            let img = await repo.photo(s)
            log("photo read \(s.fullName): \(img == nil ? "none" : "\(Int(img!.size.width))x\(Int(img!.size.height))")")
        }
        // 3) raw writes past the app's own checks
        if let cloud = repo as? CloudRepository {
            for (sid, cid) in pairs { log("raw on \(sid) as \(user.role.dbValue): " + (await cloud.debugRawWrites(studentId: sid, circleId: cid))) }
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        try? await repo.refresh()
        let after = repo.snapshot
        log("after recs=\(after.recitations.count) att=\(after.attendance.count) sync=\(repo.syncState)")
        log("done")
    }
}
#endif
