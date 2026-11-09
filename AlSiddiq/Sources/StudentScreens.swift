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
        let pickedCircle: String? = circleIdx > 0 && circles.indices.contains(circleIdx - 1) ? circles[circleIdx - 1].id : nil
        let list = Permissions.visibleStudents(user, snap).filter { (s: Student) -> Bool in
            let inCircle = circleIdx == 0 || s.circleId == pickedCircle
            let matches = needle.isEmpty || s.fullName.contains(needle) || s.phone.contains(needle)
            return inCircle && matches
        }
        ScreenList(title: "الطلاب", fab: Permissions.canEditStudents(user, snap) ? Fab(label: "طالب جديد") { router.go(.studentEdit("new", nil)) } : nil) {
            SearchField(placeholder: "بحث باسم الطالب", text: $q)
            ChoiceChips(options: options, selected: circleIdx) { circleIdx = $0 }
            Text(Fmt.students(list.count)).font(T.labelMedium).foregroundColor(Brand.muted)
            if list.isEmpty { EmptyState(title: "لا يوجد طلاب", message: needle.isEmpty ? (Permissions.canEditStudents(user, snap) ? "أضف أول طالب للمركز" : "تضيفهم الإدارة أو المعلمون") : "لا نتائج مطابقة للبحث") }
            ForEach(list) { s in
                StudentRow(s: s, snap: snap, onTap: { router.go(.student(s.id)) }) {
                    Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundColor(Brand.muted)
                }
            }
        }
    }
}

/// The student progress dashboard (everyone sees it; only admin/teachers can change things).
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
            HStack(spacing: 12) {
                StudentAvatar(s: s, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.fullName).font(T.titleMedium).foregroundColor(Brand.ink)
                    Text(snap.circle(s.circleId)?.name ?? "بدون حلقة").font(T.bodySmall).foregroundColor(Brand.muted)
                }
                Spacer()
            }
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
                KeyValueRow(key: "المعلم", value: teacherName(snap))
                KeyValueRow(key: "تاريخ الالتحاق", value: Days.parse(s.joinedOn).map { Fmt.date($0) } ?? s.joinedOn)
                if let b = s.birthYear { KeyValueRow(key: "سنة الميلاد", value: "\(b)") }
                KeyValueRow(key: "الحالة", value: s.status.label)
                if !s.notes.isEmpty { KeyValueRow(key: "ملاحظات", value: s.notes) }
            }
        }
    }
}

extension StudentDashboard {
    func teacherName(_ snap: CenterSnapshot) -> String {
        guard let c = snap.circle(s.circleId), let t = snap.teacherName(of: c) else { return "—" }
        return t
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
                if Permissions.canEditStudent(user, s, snap) {
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
    @State private var picker: PhotoSource?
    @State private var pendingPhoto: Data?
    @State private var removePhoto = false

    var body: some View {
        let snap = model.snap
        let existing = snap.student(id)
        ScreenList(title: existing == nil ? "طالب جديد" : "تعديل بيانات الطالب") {
            photoCard(existing)
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    Field(label: "اسم الطالب الكامل", text: $name)
                    Field(label: "جوال الطالب أو ولي الأمر", text: $phone, keyboard: .phonePad)
                    HStack(spacing: 10) {
                        Field(label: "سنة الميلاد", text: Binding(get: { birth }, set: { v in birth = String(v.filter { $0.isNumber }.prefix(4)) }), keyboard: .numberPad)
                        Field(label: "الهدف (أجزاء)", text: Binding(get: { goal }, set: { v in goal = String(v.filter { $0.isNumber }.prefix(2)) }), keyboard: .numberPad)
                    }
                    SelectorField(label: "الحلقة", value: snap.circle(circleId)?.name ?? "اختر الحلقة") {
                        dialogs.show(PickerDialog(title: "اختر الحلقة", items: Permissions.editableCircles(user, snap), label: { $0.name }) { circleId = $0.id })
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
                let photo = pendingPhoto, drop = removePhoto
                model.run(existing == nil ? "تمت إضافة الطالب" : "تم الحفظ", {
                    let saved = try await model.repo.saveStudent(st)
                    if let p = photo { try await model.repo.setStudentPhoto(studentId: saved.id, jpeg: p) }
                    else if drop && saved.photoPath != nil { try await model.repo.setStudentPhoto(studentId: saved.id, jpeg: nil) }
                    return saved
                }) { _ in router.back() }
            }
            if let ex = existing, Permissions.canDismissStudent(user, ex, snap) {
                // v3.6: «فصل الطالب» — the row stays on the server; a teacher's dismissal reaches the admin's bell
                Button {
                    dialogs.show(ConfirmDialog(title: "فصل الطالب؟",
                                               message: user.role == .teacher ? "سيُخفى «\(ex.fullName)» من القوائم، ويصل إشعار للإدارة." : "سيُخفى «\(ex.fullName)» من القوائم.",
                                               confirm: "فصل", destructive: true) {
                        model.run("فُصل الطالب", { try await model.repo.dismissStudent(ex.id) }) { _ in router.popToRoot() }
                    })
                } label: { Text("فصل الطالب").font(T.labelLarge).foregroundColor(Brand.maroon).frame(maxWidth: .infinity).padding(.vertical, 10) }
                .accessibilityIdentifier("dismissStudent")
            }
            if let ex = existing, Permissions.canDeleteStudents(user) {
                Button {
                    dialogs.show(ConfirmDialog(title: "حذف الطالب؟", message: "ستُحذف جميع سجلاته وحضوره ومكافآته نهائياً.", confirm: "حذف", destructive: true) {
                        model.run("حُذف الطالب", { try await model.repo.deleteStudent(ex.id) }) { _ in router.popToRoot() }
                    })
                } label: { Text("حذف الطالب").font(T.labelLarge).foregroundColor(Brand.red).frame(maxWidth: .infinity).padding(.vertical, 10) }
            }
        }
        .sheet(item: $picker) { src in
            PhotoPickerSheet(source: src) { img in
                picker = nil
                if let img = img, let data = PhotoTools.jpeg512(img) { pendingPhoto = data; removePhoto = false }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = model.snap.student(id) {
                name = e.fullName; phone = e.phone; birth = e.birthYear.map(String.init) ?? ""
                circleId = e.circleId; goal = String(e.goalJuz); status = e.status; notes = e.notes
            } else {
                // v3.3: a teacher adds into his own circle (preset, or his first one)
                let mine = Permissions.editableCircles(user, model.snap)
                circleId = presetCircle.flatMap { p in mine.contains { $0.id == p } ? p : nil } ?? (user.role == .teacher ? mine.first?.id : presetCircle)
            }
        }
    }
}

extension StudentEditScreen {
    @ViewBuilder
    func photoCard(_ existing: Student?) -> some View {
        AppCard {
            HStack(spacing: 14) {
                ZStack {
                    if let d = pendingPhoto, let img = UIImage(data: d) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(SwiftUI.Circle())
                    } else if let e = existing, e.photoPath != nil, !removePhoto {
                        StudentAvatar(s: e, size: 72)
                    } else {
                        Avatar(name: name.isEmpty ? "؟" : name, size: 72)
                    }
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 8) {
                    Text("صورة الطالب (اختياري)").font(T.titleSmall).foregroundColor(Brand.ink)
                    HStack(spacing: 8) {
                        Button { picker = .library } label: { Label("من الصور", systemImage: "photo.on.rectangle").font(T.labelMedium) }
                            .buttonStyle(.bordered).tint(Brand.navy)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { picker = .camera } label: { Label("الكاميرا", systemImage: "camera").font(T.labelMedium) }
                                .buttonStyle(.bordered).tint(Brand.navy)
                        }
                    }
                    if pendingPhoto != nil || (existing?.photoPath != nil && !removePhoto) {
                        Button { pendingPhoto = nil; removePhoto = true } label: {
                            Text("إزالة الصورة").font(T.labelMedium).foregroundColor(Brand.red)
                        }
                    }
                }
                Spacer(minLength: 0)
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
        ScreenList(title: "سجل \(s?.fullName ?? "")") {
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
