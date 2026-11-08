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
        let top = AdminHome.topStudents(snap, since: weekStart)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeader(greeting: "السلام عليكم ورحمة الله", title: snap.center.name,
                           subtitle: "\(Fmt.dayTitle(today)) • \(Fmt.hijri(today))", unread: snap.unreadCount) { router.go(.announcements) }
                VStack(alignment: .leading, spacing: 0) {
                    RoleStrip(user: user).padding(.top, 12)
                    if model.isDemo { DemoBanner().padding(.top, 10) }
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
                        QuickAction(label: "كلمات السر", icon: "key") { router.go(.passwords) }
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

extension AdminHome {
    static func topStudents(_ snap: CenterSnapshot, since: Date) -> [(Student, Int)] {
        var out: [(Student, Int)] = []
        for s in snap.students {
            var n = 0
            for r in snap.recitations where r.studentId == s.id && r.kind == .hifz && Days.dayOf(r.recordedAt) >= since { n += Stats.ayatOf(r) }
            out.append((s, n))
        }
        return Array(out.sorted { $0.1 > $1.1 }.prefix(5))
    }
}

struct TeacherHome: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    /// v3.1: the shared teachers' password opens every circle; the picked circle is remembered on this phone.
    @AppStorage("teacherCircleId") private var circleId = ""

    var body: some View {
        let snap = model.snap
        let circles = Permissions.visibleCircles(user, snap)
        let circle = circles.first { $0.id == circleId } ?? circles.first
        let students = circle.map { c in snap.studentsIn(c.id).sorted { $0.fullName < $1.fullName } } ?? []
        let stats = Stats.forCenter(snap, students)
        let today = Days.today
        let logged = Set(snap.recitations.filter { Days.dayOf($0.recordedAt) == today }.map { $0.studentId })
        let doneCount = students.filter { logged.contains($0.id) }.count
        let pending = students.count - doneCount
        let ids = Set(students.map { $0.id })
        let recent = snap.recitations.filter { ids.contains($0.studentId) }.sorted { $0.recordedAt > $1.recordedAt }.prefix(6)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeader(greeting: "السلام عليكم", title: "قسم المعلمين", subtitle: "\(Fmt.dayTitle(today)) • \(Fmt.hijri(today))",
                           unread: snap.unreadCount) { router.go(.announcements) }
                VStack(alignment: .leading, spacing: 0) {
                    RoleStrip(user: user).padding(.top, 12)
                    if model.isDemo { DemoBanner().padding(.top, 10) }
                    SectionHeader(title: "الحلقة")
                    if circles.isEmpty {
                        EmptyState(title: "لا توجد حلقات", message: "تنشئها الإدارة من الإعدادات ← الإدارة")
                    } else {
                        ChoiceChips(options: circles.map { $0.name }, selected: circles.firstIndex { $0.id == circle?.id } ?? 0) { circleId = circles[$0].id }
                            .accessibilityIdentifier("circlePicker")
                    }
                    if let c = circle {
                        AppCard {
                            HStack(spacing: 14) {
                                ProgressRing(progress: students.isEmpty ? 0 : Double(doneCount) / Double(students.count), size: 92, stroke: 10,
                                             color: Brand.green, track: Brand.greenSoft) {
                                    Text("\(doneCount)/\(students.count)").font(T.titleMedium).foregroundColor(Brand.ink)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("تسميع اليوم • \(c.name)").font(T.titleSmall).foregroundColor(Brand.ink)
                                    Text(pending == 0 ? "أحسنت! سُجّل جميع الطلاب" : "بقي \(pending) طالب لم يُسجَّل لهم").font(T.bodySmall).foregroundColor(Brand.muted)
                                    Button { router.go(.circle(c.id)) } label: {
                                        HStack(spacing: 4) { Image(systemName: "plus"); Text("تسجيل الآن").font(T.labelLarge) }
                                            .foregroundColor(.white).padding(.horizontal, 16).frame(height: 40)
                                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.navy))
                                    }
                                    .buttonStyle(PressableStyle()).padding(.top, 6)
                                }
                                Spacer(minLength: 0)
                            }
                        }.padding(.top, 10)
                        HStack(spacing: 10) {
                            StatTile(label: "طلاب الحلقة", value: "\(students.count)", icon: "graduationcap", tint: Brand.navy) { router.go(.circle(c.id)) }
                            StatTile(label: "آيات الأسبوع", value: "\(stats.ayatThisWeek)", icon: "book", tint: Brand.maroon)
                            StatTile(label: "حضور اليوم", value: stats.attendanceToday > 0 ? Fmt.pct(stats.attendanceToday) : "—", icon: "checklist", tint: Brand.green) { router.go(.attendance(c.id)) }
                        }.padding(.top, 10)
                        SectionHeader(title: "أدوات")
                        HStack(spacing: 10) {
                            QuickAction(label: "تقرير اليوم", icon: "doc.text") { router.go(.circleReport(c.id)) }
                            QuickAction(label: "الحضور", icon: "checklist") { router.go(.attendance(c.id)) }
                            QuickAction(label: "طالب جديد", icon: "person.badge.plus") { router.go(.studentEdit("new", c.id)) }
                        }
                        SectionHeader(title: "آخر التسجيلات في الحلقة")
                        if recent.isEmpty { EmptyState(title: "لا تسجيلات بعد", message: "اضغط «تسجيل الآن» واختر الطالب") }
                        VStack(spacing: 10) {
                            ForEach(Array(recent)) { r in RecordRow(r: r, snap: snap, showStudent: true) }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .background(Brand.bg.ignoresSafeArea())
    }
}
