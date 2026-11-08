import SwiftUI

struct CirclesScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        let circles = Permissions.visibleCircles(user, snap)
        let canManage = Permissions.canManageCircles(user)
        ScreenList(title: "الحلقات", fab: canManage ? Fab(label: "حلقة جديدة") { router.go(.circleEdit("new")) } : nil) {
            if circles.isEmpty {
                EmptyState(title: "لا توجد حلقات", message: canManage ? "أنشئ أول حلقة للمركز" : "تنشئها الإدارة من الإعدادات ← الإدارة",
                           action: canManage ? "حلقة جديدة" : nil, onAction: { router.go(.circleEdit("new")) })
            }
            ForEach(circles) { c in CircleCard(c: c, snap: snap) { router.go(.circle(c.id)) } }
        }
    }
}

struct CircleDetailScreen: View {
    let user: Member
    let id: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router

    var body: some View {
        let snap = model.snap
        if let circle = snap.circle(id) {
            content(circle, snap)
        } else {
            ScreenList(title: "الحلقة") { EmptyState(title: "الحلقة غير موجودة", message: "ربما حُذفت") }
        }
    }

    private func content(_ circle: StudyCircle, _ snap: CenterSnapshot) -> some View {
        let students = snap.studentsIn(circle.id).sorted { $0.fullName < $1.fullName }
        let canTeach = Permissions.canTakeAttendance(user, circle.id, snap)
        let ids = Set(students.map { $0.id })
        let weekStart = Days.add(Days.today, -6)
        let weekRecs = snap.recitations.filter { ids.contains($0.studentId) && Days.dayOf($0.recordedAt) >= weekStart }
        let todayIso = Days.iso(Days.today)
        let loggedToday = Set(snap.recitations.filter { ids.contains($0.studentId) && Days.dayOf($0.recordedAt) == Days.today }.map { $0.studentId })
        let teacherName = snap.teacherName(of: circle)
        return ScreenList(title: circle.name, actions: {
            if Permissions.canManageCircles(user) {
                Button { router.go(.circleEdit(circle.id)) } label: { Image(systemName: "pencil").font(.system(size: 18)).foregroundColor(Brand.ink).frame(width: 44, height: 44) }
                    .accessibilityLabel("تعديل")
            }
        }) {
            AppCard {
                HStack(spacing: 12) {
                    Avatar(name: teacherName ?? "؟", size: 46, color: Brand.maroon)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(teacherName ?? "بدون معلم").font(T.titleSmall).foregroundColor(Brand.ink)
                        Text([circle.level, circle.schedule].filter { !$0.isEmpty }.joined(separator: " • ")).font(T.bodySmall).foregroundColor(Brand.muted)
                    }
                    Spacer()
                }
                Spacer().frame(height: 12)
                HStack {
                    MiniStat(label: "الطلاب", value: "\(students.count)/\(circle.capacity)")
                    MiniStat(label: "سجلات الأسبوع", value: "\(weekRecs.count)")
                    MiniStat(label: "آيات الأسبوع", value: "\(weekRecs.reduce(0) { $0 + Stats.ayatOf($1) })")
                }
            }
            if user.role == .teacher && !canTeach {
                HStack(spacing: 8) {
                    Image(systemName: "eye").foregroundColor(Brand.goldInk)
                    Text("ليست حلقتك: للعرض فقط").font(T.labelLarge).foregroundColor(Brand.goldInk)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Brand.goldSoft))
                .accessibilityIdentifier("viewOnlyCircle")
            }
            if canTeach {
                HStack(spacing: 10) {
                    PrimaryButton(title: "تحضير اليوم", icon: "checklist", height: 48) { router.go(.attendance(circle.id)) }
                    OutlineButton(title: "تقرير اليوم", icon: "doc.text") { router.go(.circleReport(circle.id)) }
                }
            }
            SectionHeader(title: "الطلاب" + (canTeach ? " — اضغط لتسجيل التسميع" : ""), action: canTeach ? "إضافة طالب" : nil) {
                router.go(.studentEdit("new", circle.id))
            }
            if students.isEmpty { EmptyState(title: "لا يوجد طلاب في الحلقة", message: "أضف طلاباً من شاشة الطلاب") }
            ForEach(students) { s in
                let todayAtt = snap.attendance.first { $0.studentId == s.id && $0.day == todayIso }
                StudentRow(s: s, snap: snap, onTap: { router.go(canTeach ? .record(s.id) : .student(s.id)) }) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if loggedToday.contains(s.id) { Pill(text: "سُجّل ✓", color: Brand.green) }
                        else if canTeach { Image(systemName: "plus.circle").font(.system(size: 20)).foregroundColor(Brand.maroon) }
                        if let a = todayAtt { Pill(text: a.status.label, color: attendanceColor(a.status)) }
                        Button { router.go(.student(s.id)) } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 15)).foregroundColor(Brand.navy).frame(width: 30, height: 30)
                        }
                        .accessibilityLabel("ملف الطالب")
                    }
                }
            }
        }
    }
}

struct CircleEditScreen: View {
    let user: Member
    let id: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var dialogs: DialogHost
    @State private var loaded = false
    @State private var name = ""
    @State private var teacherName: String?
    @State private var teacherId: String?
    @State private var level = ""
    @State private var schedule = ""
    @State private var capacity = "15"
    let levels = ["تمهيدي", "متوسط", "متقدم", "مراجعة", "إجازة"]

    var body: some View {
        let snap = model.snap
        let existing = snap.circle(id)
        ScreenList(title: existing == nil ? "حلقة جديدة" : "تعديل الحلقة") {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    Field(label: "اسم الحلقة", text: $name)
                    SelectorField(label: "المعلم (اختياري)", value: teacherName ?? "اختر المعلم") {
                        dialogs.show(PickerDialog(title: "اختر المعلم", items: [TeacherName(id: "", name: "بدون معلم")] + snap.teachers(), label: { $0.name }) {
                            teacherName = $0.id.isEmpty ? nil : $0.name
                            teacherId = $0.id.isEmpty ? nil : $0.id
                        })
                    }
                    Text("المستوى").font(T.labelMedium).foregroundColor(Brand.muted).padding(.top, 2)
                    ChoiceChips(options: levels, selected: levels.firstIndex(of: level) ?? -1) { level = levels[$0] }
                    Field(label: "الموعد (مثال: بعد العصر • السبت–الأربعاء)", text: $schedule)
                    Field(label: "السعة القصوى", text: Binding(get: { capacity }, set: { v in capacity = String(v.filter { $0.isNumber }.prefix(3)) }), keyboard: .numberPad)
                }
            }
            PrimaryButton(title: existing == nil ? "إنشاء الحلقة" : "حفظ") {
                var c = existing ?? StudyCircle(id: "", name: "", teacherId: nil)
                c.name = name.trimmingCharacters(in: .whitespaces)
                c.teacherName = teacherName
                c.teacherId = teacherId   // v3.3: the teacher ACCOUNT who may edit this circle
                c.level = level
                c.schedule = schedule.trimmingCharacters(in: .whitespaces)
                c.capacity = Int(capacity) ?? 15
                model.run(existing == nil ? "تم إنشاء الحلقة" : "تم الحفظ", { try await model.repo.saveCircle(c) }) { _ in router.back() }
            }
            if let ex = existing {
                Button {
                    dialogs.show(ConfirmDialog(title: "حذف الحلقة؟", message: "سيبقى الطلاب وسجلاتهم، لكن يصبحون بدون حلقة.", confirm: "حذف", destructive: true) {
                        model.run("حُذفت الحلقة", { try await model.repo.deleteCircle(ex.id) }) { _ in router.popToRoot() }
                    })
                } label: { Text("حذف الحلقة").font(T.labelLarge).foregroundColor(Brand.red).frame(maxWidth: .infinity).padding(.vertical, 10) }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = model.snap.circle(id) {
                name = e.name; teacherName = model.snap.teacherName(of: e); teacherId = e.teacherId; level = e.level; schedule = e.schedule; capacity = String(e.capacity)
            }
        }
    }
}
