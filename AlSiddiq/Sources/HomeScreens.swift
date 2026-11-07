import SwiftUI

struct AdminHome: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router

    var body: some View {
        let snap = model.snap
        let stats = Stats.forCenter(snap, snap.students)
        let today = Days.today
        let weekStart = Days.add(today, -6)
        let top = snap.students.map { s -> (Student, Int) in
            (s, snap.recitations.filter { $0.studentId == s.id && $0.kind == .hifz && Days.dayOf($0.recordedAt) >= weekStart }.reduce(0) { $0 + Stats.ayatOf($1) })
        }.sorted { $0.1 > $1.1 }.prefix(5)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeader(greeting: "السلام عليكم ورحمة الله", title: snap.center.name,
                           subtitle: Fmt.dayTitle(today) + " • " + Fmt.hijri(today), unread: snap.unreadCount) { router.go(.notifications) }
                VStack(alignment: .leading, spacing: 0) {
                    if model.isDemo { DemoBanner().padding(.top, 12) }
                    HStack(spacing: 10) {
                        StatTile(label: "الطلاب", value: "\(stats.students)", icon: "graduationcap", tint: Brand.navy) { router.go(.students) }
                        StatTile(label: "الحلقات", value: "\(snap.circles.count)", icon: "person.3", tint: Brand.maroon) { router.go(.circles) }
                    }.padding(.top, 12)
                    HStack(spacing: 10) {
                        StatTile(label: "تسميع اليوم", value: "\(stats.recordsToday)", icon: "book", tint: Brand.green, sub: "\(stats.ayatThisWeek) آية هذا الأسبوع")
                        StatTile(label: "حضور اليوم", value: stats.attendanceToday > 0 ? Fmt.pct(stats.attendanceToday) : "—", icon: "checklist", tint: Brand.gold,
                                 sub: stats.attendanceToday > 0 ? nil : "لم يُسجَّل بعد") { router.go(.attendance(nil)) }
                    }.padding(.top, 10)
                    SectionHeader(title: "إجراءات سريعة")
                    HStack(spacing: 10) {
                        QuickAction(label: "طالب جديد", icon: "person.badge.plus") { router.go(.studentEdit("new", nil)) }
                        QuickAction(label: "حلقة جديدة", icon: "person.3.sequence") { router.go(.circleEdit("new")) }
                        QuickAction(label: "تسجيل", icon: "square.and.pencil") { router.go(.recordStart) }
                        QuickAction(label: "إعلان", icon: "megaphone") { router.go(.announceNew) }
                    }
                    SectionHeader(title: "نشاط التسميع", action: "التقارير") { router.go(.reports) }
                    AppCard {
                        Text("عدد السجلات يومياً — آخر 14 يوماً").font(T.bodySmall).foregroundColor(Brand.muted)
                        Spacer().frame(height: 10)
                        BarChart(data: stats.dailyRecords.map { BarDatum(label: Fmt.shortDay($0.0) + " \(Days.dayOfMonth($0.0))", value: Double($0.1), detail: "\($0.1) سجل") })
                    }
                    AppCard {
                        Text("توزيع التقديرات").font(T.titleSmall).foregroundColor(Brand.ink)
                        Spacer().frame(height: 10)
                        DonutChart(slices: Grade.allCases.map { Slice(label: $0.label, value: Double(stats.gradeDistribution[$0] ?? 0), color: gradeColor($0)) },
                                   centerText: "\(stats.gradeDistribution.values.reduce(0, +))")
                    }.padding(.top, 10)
                    SectionHeader(title: "الحلقات", action: "عرض الكل") { router.go(.circles) }
                    VStack(spacing: 10) {
                        ForEach(snap.circles) { c in CircleCard(c: c, snap: snap) { router.go(.circle(c.id)) } }
                    }
                    SectionHeader(title: "الأكثر إنجازاً هذا الأسبوع")
                    AppCard(padding: 8) {
                        ForEach(Array(top.enumerated()), id: \.offset) { i, pair in
                            Button { router.go(.student(pair.0.id)) } label: {
                                HStack(spacing: 10) {
                                    Text("\(i + 1)").font(AppFont.f(14, .bold)).foregroundColor(i == 0 ? .white : Brand.navy)
                                        .frame(width: 28, height: 28).background(SwiftUI.Circle().fill(i == 0 ? Brand.gold : Brand.navySoft))
                                    Text(pair.0.fullName).font(T.bodyMedium).foregroundColor(Brand.ink)
                                    Spacer()
                                    Text("\(pair.1) آية").font(T.labelLarge).foregroundColor(Brand.navy)
                                }
                                .padding(8).contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .background(Brand.bg.ignoresSafeArea())
    }
}

struct TeacherHome: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router

    var body: some View {
        let snap = model.snap
        let circles = Permissions.visibleCircles(user, snap)
        let students = Permissions.visibleStudents(user, snap)
        let stats = Stats.forCenter(snap, students)
        let today = Days.today
        let logged = Set(snap.recitations.filter { Days.dayOf($0.recordedAt) == today }.map { $0.studentId })
        let doneCount = students.filter { logged.contains($0.id) }.count
        let pending = students.count - doneCount
        let recent = snap.recitations.filter { $0.teacherId == user.id }.sorted { $0.recordedAt > $1.recordedAt }.prefix(6)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeader(greeting: "السلام عليكم", title: user.fullName, subtitle: Fmt.dayTitle(today) + " • " + Fmt.hijri(today),
                           unread: snap.unreadCount) { router.go(.notifications) }
                VStack(alignment: .leading, spacing: 0) {
                    if model.isDemo { DemoBanner().padding(.top, 12) }
                    AppCard {
                        HStack(spacing: 14) {
                            ProgressRing(progress: students.isEmpty ? 0 : Double(doneCount) / Double(students.count), size: 92, stroke: 10,
                                         color: Brand.green, track: Brand.greenSoft) {
                                Text("\(doneCount)/\(students.count)").font(T.titleMedium).foregroundColor(Brand.ink)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("تسميع اليوم").font(T.titleSmall).foregroundColor(Brand.ink)
                                Text(pending == 0 ? "أحسنت! سُجّل جميع الطلاب" : "بقي \(pending) طالب لم يُسجَّل لهم").font(T.bodySmall).foregroundColor(Brand.muted)
                                Button { router.go(.recordStart) } label: {
                                    HStack(spacing: 4) { Image(systemName: "plus"); Text("تسجيل الآن").font(T.labelLarge) }
                                        .foregroundColor(.white).padding(.horizontal, 16).frame(height: 40)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.navy))
                                }
                                .buttonStyle(PressableStyle()).padding(.top, 6)
                            }
                            Spacer(minLength: 0)
                        }
                    }.padding(.top, 12)
                    HStack(spacing: 10) {
                        StatTile(label: "طلابي", value: "\(students.count)", icon: "graduationcap", tint: Brand.navy)
                        StatTile(label: "آيات الأسبوع", value: "\(stats.ayatThisWeek)", icon: "book", tint: Brand.maroon)
                        StatTile(label: "حضور اليوم", value: stats.attendanceToday > 0 ? Fmt.pct(stats.attendanceToday) : "—", icon: "checklist", tint: Brand.green) { router.go(.attendance(nil)) }
                    }.padding(.top, 10)
                    SectionHeader(title: "حلقاتي")
                    VStack(spacing: 10) {
                        ForEach(circles) { c in CircleCard(c: c, snap: snap) { router.go(.circle(c.id)) } }
                    }
                    SectionHeader(title: "أدوات")
                    HStack(spacing: 10) {
                        QuickAction(label: "المكافآت", icon: "trophy") { router.go(.rewards) }
                        QuickAction(label: "التقارير", icon: "chart.bar.xaxis") { router.go(.reports) }
                        QuickAction(label: "الإعلانات", icon: "megaphone") { router.go(.announcements) }
                    }
                    SectionHeader(title: "آخر ما سجّلت")
                    VStack(spacing: 10) {
                        ForEach(Array(recent)) { r in RecordRow(r: r, snap: snap, showStudent: true) }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .background(Brand.bg.ignoresSafeArea())
    }
}

struct StudentHome: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HomeHeader(greeting: "السلام عليكم", title: user.fullName, subtitle: "«خيركم من تعلّم القرآن وعلّمه»", unread: snap.unreadCount) { router.go(.notifications) }
                Group {
                    if model.isDemo { DemoBanner() }
                    if let s = snap.student(user.studentId) {
                        StudentDashboard(s: s, user: user)
                    } else {
                        EmptyState(title: "الحساب غير مرتبط بسجل طالب", message: "تواصل مع إدارة المركز")
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .background(Brand.bg.ignoresSafeArea())
    }
}

struct ParentHome: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        let kids = Permissions.visibleStudents(user, snap)
        let todayIso = Days.iso(Days.today)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeader(greeting: "مرحباً بك", title: user.fullName, subtitle: "تابع حفظ أبنائك وحضورهم يوماً بيوم", unread: snap.unreadCount) { router.go(.notifications) }
                VStack(alignment: .leading, spacing: 0) {
                    if model.isDemo { DemoBanner().padding(.top, 12) }
                    SectionHeader(title: "أبنائي")
                    if kids.isEmpty { EmptyState(title: "لا يوجد أبناء مرتبطون", message: "تواصل مع إدارة المركز لربط حسابك بأبنائك") }
                    VStack(spacing: 12) {
                        ForEach(kids) { s in
                            let st = Stats.forStudent(s, snap)
                            let todayAtt = snap.attendance.first { $0.studentId == s.id && $0.day == todayIso }
                            AppCard(onTap: { router.go(.student(s.id)) }) {
                                HStack(spacing: 14) {
                                    ProgressRing(progress: st.goalProgress, size: 84, stroke: 9) {
                                        Text(Fmt.pct(st.goalProgress)).font(T.labelLarge).foregroundColor(Brand.navy)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.fullName).font(T.titleMedium).foregroundColor(Brand.ink)
                                        Text(snap.circle(s.circleId)?.name ?? "").font(T.bodySmall).foregroundColor(Brand.muted)
                                        Text("\(Fmt.one(st.juzEquivalent)) جزء من \(s.goalJuz) • \(st.points) نقطة").font(T.bodySmall).foregroundColor(Brand.ink).padding(.top, 4)
                                        HStack(spacing: 6) {
                                            if let a = todayAtt { Pill(text: "اليوم: \(a.status.label)", color: attendanceColor(a.status)) }
                                            if let r = st.lastRecord { Pill(text: r.grade.label, color: gradeColor(r.grade)) }
                                        }.padding(.top, 4)
                                    }
                                    Spacer(minLength: 0)
                                }
                                if let r = st.lastRecord {
                                    Divider1().padding(.vertical, 9)
                                    Text("آخر تسميع: \(r.kind.label) — \(Stats.describeRange(r)) • \(Fmt.relative(r.recordedAt))").font(T.bodySmall).foregroundColor(Brand.muted)
                                }
                            }
                        }
                    }
                    SectionHeader(title: "إعلانات المركز", action: "الكل") { router.go(.announcements) }
                    VStack(spacing: 8) {
                        ForEach(Array(snap.announcements.sorted { $0.createdAt > $1.createdAt }.prefix(2))) { a in
                            AppCard(padding: 12, onTap: { router.go(.announcements) }) {
                                Text(a.title).font(T.titleSmall).foregroundColor(Brand.ink)
                                Text(a.body).font(T.bodySmall).foregroundColor(Brand.muted).lineLimit(2)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .background(Brand.bg.ignoresSafeArea())
    }
}
