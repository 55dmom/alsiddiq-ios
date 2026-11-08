import SwiftUI

struct AttendanceScreen: View {
    let user: Member
    let circleId: String?
    var body: some View {
        AttendanceTaking(user: user, circleId: circleId)
    }
}

private struct AttendanceTaking: View {
    let user: Member
    let circleId: String?
    @EnvironmentObject var model: AppModel
    @State private var circleIdx = -1
    @State private var day = Days.today
    @State private var marks: [String: AttendanceStatus] = [:]
    @State private var loadedKey = ""

    var body: some View {
        let snap = model.snap
        let circles = Permissions.editableCircles(user, snap)   // v3.3: attendance in his own circle(s) only
        let idx = circleIdx >= 0 ? circleIdx : max(circles.firstIndex { $0.id == circleId } ?? 0, 0)
        let circle = circles.indices.contains(idx) ? circles[idx] : nil
        let students = circle.map { c in snap.studentsIn(c.id).sorted { $0.fullName < $1.fullName } } ?? []
        let dayIso = Days.iso(day)
        var saved: [String: AttendanceStatus] = [:]
        for a in snap.attendance where a.day == dayIso && a.circleId == circle?.id { saved[a.studentId] = a.status }
        let cid: String = circle?.id ?? ""
        let savedSig: String = saved.map { "\($0.key)=\($0.value.rawValue)" }.sorted().joined(separator: ",")
        let key = "\(cid)|\(dayIso)|\(savedSig)"
        let dirty = students.contains { marks[$0.id] != saved[$0.id] }
        let p = students.filter { marks[$0.id]?.isPresent == true }.count
        let a = students.filter { marks[$0.id] == .absent }.count
        let unset = students.filter { marks[$0.id] == nil }.count
        let canForward = day < Days.today

        return ScreenList(title: "الحضور والغياب") {
            ChoiceChips(options: circles.map { $0.name }, selected: idx) { circleIdx = $0 }
            AppCard(padding: 8) {
                HStack {
                    Button { day = Days.add(day, -1) } label: {
                        Image(systemName: "chevron.backward").font(.system(size: 17, weight: .semibold)).foregroundColor(Brand.ink).frame(width: 44, height: 44)
                    }.accessibilityLabel("اليوم السابق")
                    Spacer()
                    VStack(spacing: 1) {
                        Text(Fmt.dayTitle(day)).font(T.titleSmall).foregroundColor(Brand.ink)
                        Text(Fmt.hijri(day)).font(T.labelSmall).foregroundColor(Brand.muted)
                    }
                    Spacer()
                    Button { if canForward { day = Days.add(day, 1) } } label: {
                        Image(systemName: "chevron.forward").font(.system(size: 17, weight: .semibold)).foregroundColor(canForward ? Brand.ink : Brand.line).frame(width: 44, height: 44)
                    }.disabled(!canForward).accessibilityLabel("اليوم التالي")
                }
            }
            HStack(spacing: 6) {
                Pill(text: "حاضر \(p)", color: Brand.green)
                Pill(text: "غائب \(a)", color: Brand.red)
                Pill(text: "لم يُحدَّد \(unset)", color: Brand.muted)
                Spacer()
                TextAction(title: "البقية حاضرون", color: Brand.navy) {
                    for s in students where marks[s.id] == nil { marks[s.id] = .present }
                }
            }
            if students.isEmpty { EmptyState(title: "لا يوجد طلاب", message: "اختر حلقة فيها طلاب") }
            ForEach(students) { s in
                AppCard(padding: 12) {
                    HStack(spacing: 10) {
                        Avatar(name: s.fullName, size: 36)
                        Text(s.fullName).font(T.titleSmall).foregroundColor(Brand.ink)
                        Spacer()
                    }
                    Spacer().frame(height: 8)
                    HStack(spacing: 6) {
                        ForEach(AttendanceStatus.allCases) { st in
                            let sel = marks[s.id] == st
                            let col = attendanceColor(st)
                            Button { withAnimation(.easeOut(duration: 0.12)) { marks[s.id] = st } } label: {
                                Text(st.label).font(T.labelMedium).foregroundColor(sel ? .white : col)
                                    .frame(maxWidth: .infinity).frame(height: 38)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(sel ? col : col.opacity(0.08)))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            if let c = circle, !students.isEmpty {
                PrimaryButton(title: dirty ? "حفظ الحضور" : "محفوظ ✓", enabled: dirty) {
                    var m: [String: AttendanceStatus] = [:]
                    for s in students { if let v = marks[s.id] { m[s.id] = v } }
                    model.run(nil, { try await model.repo.saveAttendance(circleId: c.id, day: dayIso, marks: m) }) { n in model.say("حُفظ حضور \(n) طالب") }
                }
                Text("الغائبون يظهرون في «تقرير اليوم» للحلقة.").font(T.labelSmall).foregroundColor(Brand.muted)
            }
        }
        .onAppear { sync(key, saved) }
        .onChange(of: key) { k in sync(k, saved) }
    }

    private func sync(_ k: String, _ saved: [String: AttendanceStatus]) {
        guard k != loadedKey else { return }
        loadedKey = k
        marks = saved
    }
}

private struct AttendanceHistory: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @State private var idx = 0
    var body: some View {
        let snap = model.snap
        let kids = Permissions.visibleStudents(user, snap)
        let s = kids.indices.contains(idx) ? kids[idx] : nil
        let rows = snap.attendance.filter { $0.studentId == s?.id }.sorted { $0.day > $1.day }
        ScreenList(title: "الحضور") {
            if kids.count > 1 { ChoiceChips(options: kids.map { $0.fullName }, selected: idx) { idx = $0 } }
            if let s = s {
                AppCard {
                    Text("ملخص الحضور — \(s.fullName)").font(T.titleSmall).foregroundColor(Brand.ink)
                    Spacer().frame(height: 10)
                    DonutChart(slices: AttendanceStatus.allCases.map { st in Slice(label: st.label, value: Double(rows.filter { $0.status == st }.count), color: attendanceColor(st)) },
                               centerText: "\(rows.count) يوم")
                }
                SectionHeader(title: "السجل اليومي")
                if rows.isEmpty { EmptyState(title: "لا يوجد سجل حضور", message: "") }
                ForEach(rows) { a in
                    AppCard(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Days.parse(a.day).map { Fmt.dayTitle($0) } ?? a.day).font(T.bodyMedium).foregroundColor(Brand.ink)
                                Text(snap.circle(a.circleId)?.name ?? "").font(T.labelSmall).foregroundColor(Brand.muted)
                            }
                            Spacer()
                            Pill(text: a.status.label, color: attendanceColor(a.status))
                        }
                    }
                }
            } else {
                EmptyState(title: "لا يوجد أبناء مرتبطون", message: "تواصل مع إدارة المركز لربط حسابك بأبنائك")
            }
        }
    }
}

struct ReportsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var scopeIdx = 0
    @State private var rangeIdx = 1
    let ranges: [(Int, String)] = [(7, "أسبوع"), (30, "شهر"), (90, "3 أشهر")]

    private func scopedStudents(_ visible: [Student], _ circles: [StudyCircle], _ isParent: Bool) -> [Student] {
        if isParent { return visible.indices.contains(scopeIdx) ? [visible[scopeIdx]] : [] }
        if scopeIdx == 0 { return visible }
        guard circles.indices.contains(scopeIdx - 1) else { return [] }
        let cid = circles[scopeIdx - 1].id
        return visible.filter { $0.circleId == cid }
    }

    var body: some View {
        let snap = model.snap
        let visible = Permissions.visibleStudents(user, snap)
        let circles = Permissions.visibleCircles(user, snap)
        let isParent = false
        let scopeOptions = isParent ? visible.map { $0.fullName } : ["المركز كاملاً"] + circles.map { $0.name }
        let students = scopedStudents(visible, circles, isParent)
        let since = Days.add(Days.today, -(ranges[rangeIdx].0 - 1))
        let ids = Set(students.map { $0.id })
        let recs = snap.recitations.filter { ids.contains($0.studentId) && Days.dayOf($0.recordedAt) >= since }
        let att = snap.attendance.filter { ids.contains($0.studentId) && (Days.parse($0.day) ?? .distantPast) >= since }
        let present = att.filter { $0.status.isPresent }.count
        let counted = att.filter { $0.status != .excused }.count
        let hifzRecs = recs.filter { $0.kind == .hifz }
        let hifz = hifzRecs.reduce(0) { $0 + Stats.ayatOf($1) }
        let muraja = recs.filter { $0.kind != .hifz }.reduce(0) { $0 + Stats.ayatOf($1) }
        let pages = hifzRecs.reduce(0.0) { $0 + Stats.pagesOf($1) }
        let days = min(ranges[rangeIdx].0, 30)
        let series: [(Date, Int)] = (0..<days).reversed().map { back in
            let d = Days.add(Days.today, -back)
            return (d, recs.filter { Days.dayOf($0.recordedAt) == d }.reduce(0) { $0 + Stats.ayatOf($1) })
        }
        let avg = recs.isEmpty ? 0 : Double(recs.reduce(0) { $0 + $1.grade.score }) / Double(recs.count)
        let ranked: [(Student, Int)] = students.map { (s: Student) -> (Student, Int) in
            let n = hifzRecs.filter { $0.studentId == s.id }.reduce(0) { $0 + Stats.ayatOf($1) }
            return (s, n)
        }.sorted { $0.1 > $1.1 }
        let maxRank = max(ranked.map { $0.1 }.max() ?? 1, 1)

        ScreenList(title: "التقارير") {
            ChoiceChips(options: scopeOptions, selected: scopeIdx) { scopeIdx = $0 }
            SegmentedRow(options: ranges.map { $0.1 }, selected: rangeIdx) { rangeIdx = $0 }
            HStack(spacing: 10) {
                StatTile(label: "آيات حفظ جديد", value: "\(hifz)", icon: "book", tint: Brand.navy, sub: "\(Fmt.one(pages)) صفحة")
                StatTile(label: "آيات مراجعة وتسميع", value: "\(muraja)", icon: "arrow.counterclockwise", tint: Brand.maroon)
            }
            HStack(spacing: 10) {
                StatTile(label: "نسبة الحضور", value: counted > 0 ? Fmt.pct(Double(present) / Double(counted)) : "—", icon: "calendar.badge.clock", tint: Brand.green)
                StatTile(label: "متوسط التقدير", value: recs.isEmpty ? "—" : Fmt.one(avg) + "/5", icon: "star", tint: Brand.gold)
            }
            AppCard {
                Text("الآيات يومياً").font(T.titleSmall).foregroundColor(Brand.ink)
                Text("اضغط على أي عمود لرؤية قيمته").font(T.bodySmall).foregroundColor(Brand.muted)
                Spacer().frame(height: 10)
                BarChart(data: series.map { BarDatum(label: Fmt.shortDay($0.0) + " \(Days.dayOfMonth($0.0))", value: Double($0.1), detail: "\($0.1) آية") })
                    .id("bars\(scopeIdx)-\(rangeIdx)")
            }
            AppCard {
                Text("توزيع التقديرات").font(T.titleSmall).foregroundColor(Brand.ink)
                Spacer().frame(height: 10)
                DonutChart(slices: Grade.allCases.map { g in Slice(label: g.label, value: Double(recs.filter { $0.grade == g }.count), color: gradeColor(g)) },
                           centerText: "\(recs.count)")
                    .id("donut\(scopeIdx)-\(rangeIdx)")
            }
            if !isParent {
                SectionHeader(title: "ترتيب الطلاب حسب الحفظ")
                ForEach(Array(ranked.enumerated()), id: \.offset) { _, pair in
                    AppCard(padding: 12, onTap: { router.go(.student(pair.0.id)) }) {
                        HStack {
                            Text(pair.0.fullName).font(T.bodyMedium).foregroundColor(Brand.ink)
                            Spacer()
                            Text("\(pair.1) آية").font(T.labelLarge).foregroundColor(Brand.navy)
                        }
                        Spacer().frame(height: 6)
                        LinearMeter(progress: Double(pair.1) / Double(maxRank), color: Brand.navy)
                    }
                }
            } else if let s = students.first {
                PrimaryButton(title: "ملف \(s.fullName) الكامل", height: 50) { router.go(.student(s.id)) }
            }
        }
    }
}
