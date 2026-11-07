import SwiftUI

struct StudentsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var q = ""
    @State private var circleIdx = 0

    var body: some View {
        let snap = model.snap
        let circles = Permissions.visibleCircles(user, snap)
        let options = ["الكل"] + circles.map { $0.name }
        let needle = q.trimmingCharacters(in: .whitespaces)
        let list = Permissions.visibleStudents(user, snap).filter { s in
            (circleIdx == 0 || s.circleId == (circles.indices.contains(circleIdx - 1) ? circles[circleIdx - 1].id : nil)) &&
                (needle.isEmpty || s.fullName.contains(needle) || s.phone.contains(needle))
        }
        ScreenList(title: "الطلاب", fab: Permissions.canManageStudents(user) ? Fab(label: "طالب جديد") { router.go(.studentEdit("new", nil)) } : nil) {
            SearchField(placeholder: "بحث باسم الطالب", text: $q)
            ChoiceChips(options: options, selected: circleIdx) { circleIdx = $0 }
            Text("\(list.count) طالب").font(T.labelMedium).foregroundColor(Brand.muted)
            if list.isEmpty { EmptyState(title: "لا يوجد طلاب", message: needle.isEmpty ? "أضف أول طالب للمركز" : "لا نتائج مطابقة للبحث") }
            ForEach(list) { s in
                StudentRow(s: s, snap: snap, onTap: { router.go(.student(s.id)) }) {
                    Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundColor(Brand.muted)
                }
            }
        }
    }
}

/// The student progress dashboard, shared by the student's own home, parents and staff.
struct StudentDashboard: View {
    let s: Student
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router

    var body: some View {
        let snap = model.snap
        let stats = Stats.forStudent(s, snap)
        let recent = snap.recitations.filter { $0.studentId == s.id }.sorted { $0.recordedAt > $1.recordedAt }.prefix(5)
        VStack(alignment: .leading, spacing: 10) {
            AppCard {
                HStack(spacing: 16) {
                    ProgressRing(progress: stats.goalProgress, size: 118) {
                        VStack(spacing: 0) {
                            Text(Fmt.one(stats.juzEquivalent)).font(T.headlineSmall).foregroundColor(Brand.navy)
                            Text("من \(s.goalJuz) جزء").font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("المحفوظ").font(T.labelMedium).foregroundColor(Brand.muted)
                        Text("\(stats.memorisedAyat) آية • \(Fmt.one(stats.memorisedPages)) صفحة").font(T.titleSmall).foregroundColor(Brand.ink)
                        Text("آخر تسميع").font(T.labelMedium).foregroundColor(Brand.muted).padding(.top, 8)
                        Text(stats.lastRecord.map { Stats.describeRange($0) } ?? "لا يوجد بعد").font(T.bodyMedium).foregroundColor(Brand.ink)
                        HStack(spacing: 6) {
                            Pill(text: snap.circle(s.circleId)?.name ?? "بدون حلقة", color: Brand.navy)
                            if stats.streakDays > 1 { Pill(text: "🔥 \(stats.streakDays) أيام", color: Brand.orange) }
                        }.padding(.top, 8)
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 10) {
                StatTile(label: "الحضور", value: stats.presentDays + stats.absentDays > 0 ? Fmt.pct(stats.attendanceRate) : "—", icon: "calendar.badge.clock", tint: Brand.green, sub: "\(stats.absentDays) غياب")
                StatTile(label: "متوسط التقدير", value: stats.averageGrade > 0 ? Fmt.one(stats.averageGrade) + "/5" : "—", icon: "star", tint: Brand.gold)
                StatTile(label: "النقاط", value: "\(stats.points)", icon: "trophy", tint: Brand.maroon) { router.go(.rewards) }
            }
            AppCard {
                Text("الآيات المسجّلة يومياً").font(T.titleSmall).foregroundColor(Brand.ink)
                Text("حفظ ومراجعة — آخر 14 يوماً (اضغط على عمود)").font(T.bodySmall).foregroundColor(Brand.muted)
                Spacer().frame(height: 10)
                BarChart(data: stats.dailyAyat.map { BarDatum(label: Fmt.shortDay($0.0) + " \(Days.dayOfMonth($0.0))", value: Double($0.1), detail: "\($0.1) آية") })
                Spacer().frame(height: 12)
                HStack {
                    MiniStat(label: "حفظ (30 يوماً)", value: "\(stats.hifzAyatLast30)")
                    MiniStat(label: "مراجعة (30 يوماً)", value: "\(stats.murajaAyatLast30)")
                    MiniStat(label: "سجلات", value: "\(stats.recordsLast30)")
                }
            }
            SectionHeader(title: "أحدث السجلات", action: "السجل الكامل") { router.go(.history(s.id)) }
            if recent.isEmpty { EmptyState(title: "لا توجد سجلات", message: "سيظهر هنا كل حفظ وتسميع ومراجعة") }
            ForEach(Array(recent)) { r in RecordRow(r: r, snap: snap, showStudent: false) }
            SectionHeader(title: "بيانات الطالب")
            AppCard {
                KeyValueRow(key: "الحلقة", value: snap.circle(s.circleId)?.name ?? "—")
                KeyValueRow(key: "المعلم", value: snap.member(snap.circle(s.circleId)?.teacherId)?.fullName ?? "—")
                KeyValueRow(key: "تاريخ الالتحاق", value: Days.parse(s.joinedOn).map { Fmt.date($0) } ?? s.joinedOn)
                if let b = s.birthYear { KeyValueRow(key: "سنة الميلاد", value: "\(b)") }
                KeyValueRow(key: "الحالة", value: s.status.label)
                if user.role == .admin || user.role == .teacher {
                    let ps = snap.parentsOf(s.id).map { $0.fullName }.joined(separator: "، ")
                    KeyValueRow(key: "أولياء الأمور", value: ps.isEmpty ? "—" : ps)
                }
            }
        }
    }
}

struct StudentDetailScreen: View {
    let user: Member
    let id: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        if let s = snap.student(id) {
            let canRecord = Permissions.canRecordFor(user, s, snap)
            ScreenList(title: s.fullName, fab: canRecord ? Fab(label: "تسجيل تسميع") { router.go(.record(s.id)) } : nil, actions: {
                if Permissions.canManageStudents(user) {
                    Button { router.go(.studentEdit(s.id, nil)) } label: { Image(systemName: "pencil").font(.system(size: 18)).foregroundColor(Brand.ink).frame(width: 44, height: 44) }
                        .accessibilityLabel("تعديل")
                }
            }) {
                StudentDashboard(s: s, user: user)
            }
        } else {
            ScreenList(title: "الطالب") { EmptyState(title: "الطالب غير موجود", message: "ربما حُذف أو ليست لديك صلاحية") }
        }
    }
}

struct StudentEditScreen: View {
    let user: Member
    let id: String
    let presetCircle: String?
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var dialogs: DialogHost
    @State private var loaded = false
    @State private var name = ""
    @State private var phone = ""
    @State private var birth = ""
    @State private var circleId: String?
    @State private var goal = "5"
    @State private var status: StudentStatus = .active
    @State private var notes = ""

    var body: some View {
        let snap = model.snap
        let existing = snap.student(id)
        ScreenList(title: existing == nil ? "طالب جديد" : "تعديل بيانات الطالب") {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    Field(label: "اسم الطالب الكامل", text: $name)
                    Field(label: "جوال الطالب أو ولي الأمر", text: $phone, keyboard: .phonePad)
                    HStack(spacing: 10) {
                        Field(label: "سنة الميلاد", text: Binding(get: { birth }, set: { v in birth = String(v.filter { $0.isNumber }.prefix(4)) }), keyboard: .numberPad)
                        Field(label: "الهدف (أجزاء)", text: Binding(get: { goal }, set: { v in goal = String(v.filter { $0.isNumber }.prefix(2)) }), keyboard: .numberPad)
                    }
                    SelectorField(label: "الحلقة", value: snap.circle(circleId)?.name ?? "اختر الحلقة") {
                        dialogs.show(PickerDialog(title: "اختر الحلقة", items: snap.circles, label: { $0.name }) { circleId = $0.id })
                    }
                    Text("الحالة").font(T.labelMedium).foregroundColor(Brand.muted).padding(.top, 2)
                    ChoiceChips(options: StudentStatus.allCases.map { $0.label }, selected: StudentStatus.allCases.firstIndex(of: status) ?? 0) { status = StudentStatus.allCases[$0] }
                    Field(label: "ملاحظات", text: $notes, multiline: true, minLines: 2)
                }
            }
            PrimaryButton(title: existing == nil ? "إضافة الطالب" : "حفظ") {
                var st = existing ?? Student(id: "", fullName: "", circleId: nil, joinedOn: Days.iso(Days.today))
                st.fullName = name.trimmingCharacters(in: .whitespaces)
                st.phone = Phone.normalise(phone)
                st.birthYear = Int(birth)
                st.circleId = circleId
                st.goalJuz = min(max(Int(goal) ?? 5, 1), 30)
                st.status = status
                st.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                model.run(existing == nil ? "تمت إضافة الطالب" : "تم الحفظ", { try await model.repo.saveStudent(st) }) { _ in router.back() }
            }
            if let ex = existing {
                OutlineButton(title: "إنشاء حساب ولي أمر") { router.go(.memberEdit(.parent, "new")) }
                Button {
                    dialogs.show(ConfirmDialog(title: "حذف الطالب؟", message: "ستُحذف جميع سجلاته وحضوره ومكافآته نهائياً.", confirm: "حذف", destructive: true) {
                        model.run("حُذف الطالب", { try await model.repo.deleteStudent(ex.id) }) { _ in router.popToRoot() }
                    })
                } label: { Text("حذف الطالب").font(T.labelLarge).foregroundColor(Brand.red).frame(maxWidth: .infinity).padding(.vertical, 10) }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = model.snap.student(id) {
                name = e.fullName; phone = e.phone; birth = e.birthYear.map(String.init) ?? ""
                circleId = e.circleId; goal = String(e.goalJuz); status = e.status; notes = e.notes
            } else {
                circleId = presetCircle
            }
        }
    }
}

struct HistoryScreen: View {
    let user: Member
    let studentId: String?
    @EnvironmentObject var model: AppModel
    @State private var kind = 0

    var body: some View {
        let snap = model.snap
        let s = snap.student(studentId)
        let kinds = ["الكل"] + RecordKind.allCases.map { $0.label }
        let recs = snap.recitations.filter { $0.studentId == studentId && (kind == 0 || $0.kind == RecordKind.allCases[kind - 1]) }
            .sorted { $0.recordedAt > $1.recordedAt }
        let canDelete = s.map { Permissions.canRecordFor(user, $0, snap) } ?? false
        let groups = Dictionary(grouping: recs) { Days.dayOf($0.recordedAt) }.sorted { $0.key > $1.key }
        ScreenList(title: user.role == .student ? "سجلّي" : "سجل \(s?.fullName ?? "")") {
            ChoiceChips(options: kinds, selected: kind) { kind = $0 }
            if recs.isEmpty { EmptyState(title: "لا توجد سجلات", message: "لم يُسجَّل شيء من هذا النوع بعد") }
            ForEach(groups, id: \.key) { g in
                Text(Fmt.dayTitle(g.key)).font(T.labelLarge).foregroundColor(Brand.navy).padding(.top, 8)
                ForEach(g.value) { r in
                    RecordRow(r: r, snap: snap, showStudent: false,
                              onDelete: canDelete ? { model.run("حُذف السجل", { try await model.repo.deleteRecitation(r.id) }) } : nil)
                }
            }
        }
    }
}
