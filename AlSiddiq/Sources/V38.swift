import SwiftUI

// MARK: - v3.8 (Nov 8 2026): «حضور وغياب المعلمين» and «الميزانية», both in the admin page and for the admin ONLY.
// Server tables (files/alsiddiq_app/server_v33/0015_v38_teacher_attendance.sql, 0016_v38_budget.sql):
//   teacher_attendance(id, center_id, teacher_profile_id, day, status 'present'|'absent', marked_by, created_at), unique (teacher_profile_id, day)
//   budget_entries(id, center_id, kind 'income'|'expense', amount > 0, day, student_id, note, created_by, created_at)
// RLS lets only the centre's admin read or write either table; teachers and the general view never fetch them.

enum TeacherMarkStatus: String, Codable, CaseIterable, Hashable {
    case present, absent
    var label: String { self == .present ? "حاضر" : "غائب" }
    var color: Color { self == .present ? Brand.green : Brand.red }
}

struct TeacherMark: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var teacherId: String
    /// ISO date yyyy-MM-dd
    var day: String
    var status: TeacherMarkStatus
    var markedBy: String? = nil
}

enum BudgetKind: String, Codable, CaseIterable, Hashable {
    case income, expense
    var label: String { self == .income ? "دخل" : "صرف" }
}

struct BudgetEntry: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var kind: BudgetKind
    /// Yemeni rial
    var amount: Double
    /// ISO date yyyy-MM-dd
    var day: String
    var studentId: String? = nil
    var note: String? = nil
    var createdBy: String? = nil
    var createdAt: Date = Date()
}

enum Money {
    private static let f: NumberFormatter = {
        let f = NumberFormatter(); f.locale = Locale(identifier: "ar@numbers=arab"); f.numberStyle = .decimal
        f.usesGroupingSeparator = true; f.maximumFractionDigits = 2; return f
    }()
    static func yer(_ v: Double) -> String { (f.string(from: NSNumber(value: v)) ?? "\(v)") + " ريال" }
    /// Reads an amount typed with Arabic-Indic or Latin digits («٥٠٠٠», «5,000», «١٢٠٫٥»).
    static func parse(_ s: String) -> Double? {
        var out = ""
        for ch in s {
            if let v = ch.wholeNumberValue, ch.isNumber { out.append(String(v)) }
            else if ch == "." || ch == "٫" { out.append(".") }
        }
        guard let v = Double(out), v > 0 else { return nil }
        return v
    }
}

extension Rows {
    static func teacherMark(_ o: JSON) -> TeacherMark? {
        guard let id = o["id"] as? String, let t = o["teacher_profile_id"] as? String, let day = o["day"] as? String,
              let st = TeacherMarkStatus(rawValue: ((o["status"] as? String) ?? "").lowercased()) else { return nil }
        return TeacherMark(id: id, teacherId: t, day: String(day.prefix(10)), status: st, markedBy: o["marked_by"] as? String)
    }
    static func budgetEntry(_ o: JSON) -> BudgetEntry? {
        guard let id = o["id"] as? String, let k = BudgetKind(rawValue: ((o["kind"] as? String) ?? "").lowercased()) else { return nil }
        let amount: Double = (o["amount"] as? NSNumber)?.doubleValue ?? Double((o["amount"] as? String) ?? "") ?? 0
        return BudgetEntry(id: id, kind: k, amount: amount, day: String(((o["day"] as? String) ?? "").prefix(10)),
                           studentId: o["student_id"] as? String, note: o["note"] as? String,
                           createdBy: o["created_by"] as? String, createdAt: ts(o["created_at"]))
    }
}

private func monthKey(_ isoDay: String) -> String { String(isoDay.prefix(7)) }

// MARK: «حضور وغياب المعلمين»

struct TeacherAttendanceScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @State private var date = Days.today
    @State private var marks: [String: TeacherMarkStatus] = [:]
    @State private var loadedDay = ""

    var body: some View {
        let snap = model.snap
        let teachers = snap.teachers()
        let all = snap.teacherMarks ?? []
        let day = Days.iso(date)
        ScreenList(title: "حضور وغياب المعلمين") {
            AppCard {
                DatePicker("التاريخ", selection: $date, in: ...Date(), displayedComponents: .date)
                    .font(T.titleSmall).foregroundColor(Brand.ink).tint(Brand.navy)
                Text(Fmt.dayTitle(date) + " • " + Fmt.hijri(date)).font(T.bodySmall).foregroundColor(Brand.muted).padding(.top, 6)
            }
            if teachers.isEmpty {
                EmptyState(title: "لا يوجد معلمون", message: "أضف المعلمين من «المعلمون» في الإدارة")
            }
            ForEach(teachers) { t in
                AppCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t.name).font(T.titleSmall).foregroundColor(Brand.ink)
                        let sel = marks[t.id].map { TeacherMarkStatus.allCases.firstIndex(of: $0) ?? -1 } ?? -1
                        SegmentedRow(options: TeacherMarkStatus.allCases.map { $0.label }, selected: sel,
                                     colors: TeacherMarkStatus.allCases.map { $0.color }) { i in marks[t.id] = TeacherMarkStatus.allCases[i] }
                    }
                }
                .accessibilityIdentifier("teacherMark_" + t.id)
            }
            if !teachers.isEmpty {
                PrimaryButton(title: "حفظ", enabled: !marks.isEmpty) {
                    let m = marks
                    model.run("تم حفظ حضور المعلمين", { try await model.repo.saveTeacherAttendance(day: day, marks: m) })
                }
                .accessibilityIdentifier("saveTeacherAttendance")
            }

            // the month of the chosen date: each teacher's count
            let month = monthKey(day)
            SectionHeader(title: "عدد أيام الشهر")
            AppCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(teachers) { t in
                        let mine = all.filter { $0.teacherId == t.id && monthKey($0.day) == month }
                        HStack {
                            Text(t.name).font(T.bodyMedium).foregroundColor(Brand.ink).lineLimit(1)
                            Spacer()
                            Text("حاضر \(mine.filter { $0.status == .present }.count)").font(T.labelLarge).foregroundColor(Brand.green)
                            Text("•").foregroundColor(Brand.muted)
                            Text("غائب \(mine.filter { $0.status == .absent }.count)").font(T.labelLarge).foregroundColor(Brand.red)
                        }
                    }
                    if teachers.isEmpty { Text("—").foregroundColor(Brand.muted) }
                }
            }

            // history by date, newest first; tap a day to open it above
            let days = Array(Set(all.map { $0.day })).sorted(by: >)
            SectionHeader(title: "السجل حسب التاريخ")
            if days.isEmpty { Text("لم يُسجَّل شيء بعد").font(T.bodySmall).foregroundColor(Brand.muted) }
            ForEach(days.prefix(60), id: \.self) { d in
                let rows = all.filter { $0.day == d }
                let present = rows.filter { $0.status == .present }.compactMap { r in snap.member(r.teacherId)?.fullName }
                let absent = rows.filter { $0.status == .absent }.compactMap { r in snap.member(r.teacherId)?.fullName }
                AppCard(padding: 12, onTap: { if let x = Days.parse(d) { date = x } }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Days.parse(d).map { Fmt.dayTitle($0) } ?? d).font(T.titleSmall).foregroundColor(Brand.ink)
                        if !present.isEmpty { Text("حاضر: " + present.joined(separator: "، ")).font(T.bodySmall).foregroundColor(Brand.green) }
                        if !absent.isEmpty { Text("غائب: " + absent.joined(separator: "، ")).font(T.bodySmall).foregroundColor(Brand.red) }
                    }
                }
            }
        }
        .onAppear { loadMarks(day) }
        .onChange(of: date) { d in loadMarks(Days.iso(d)) }
    }

    private func loadMarks(_ day: String) {
        guard day != loadedDay else { return }
        loadedDay = day
        var m: [String: TeacherMarkStatus] = [:]
        for r in (model.snap.teacherMarks ?? []) where r.day == day { m[r.teacherId] = r.status }
        marks = m
    }
}

// MARK: «الميزانية»

struct BudgetScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var period = 0   // 0 الشهر, 1 الكل
    @State private var adding: BudgetKind? = nil
    @State private var editing: BudgetEntry? = nil

    var body: some View {
        let snap = model.snap
        let thisMonth = monthKey(Days.iso(Days.today))
        let entries = (snap.budget ?? []).filter { period == 1 || monthKey($0.day) == thisMonth }
            .sorted { ($0.day, $0.createdAt) > ($1.day, $1.createdAt) }
        let income = entries.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        let expense = entries.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        ScreenList(title: "الميزانية") {
            SegmentedRow(options: ["الشهر", "الكل"], selected: period) { period = $0 }
            AppCard {
                VStack(spacing: 10) {
                    sumRow("إجمالي الدخل", income, Brand.green)
                    sumRow("إجمالي الصرف", expense, Brand.red)
                    Rectangle().fill(Brand.line).frame(height: 1)
                    sumRow("المتبقي", income - expense, income - expense >= 0 ? Brand.navy : Brand.red, big: true)
                }
            }
            .accessibilityIdentifier("budgetSummary")
            HStack(spacing: 10) {
                PrimaryButton(title: "دخل: اشتراك طالب", icon: "plus") { adding = .income }
                    .accessibilityIdentifier("addIncome")
                PrimaryButton(title: "صرف", icon: "minus") { adding = .expense }
                    .accessibilityIdentifier("addExpense")
            }
            SectionHeader(title: "السجل")
            if entries.isEmpty { EmptyState(title: "لا توجد عمليات", message: period == 0 ? "لا دخل ولا صرف في هذا الشهر" : "سجّل أول دخل أو صرف") }
            ForEach(entries) { e in
                AppCard(padding: 12, onTap: { editing = e }) {
                    HStack(alignment: .top, spacing: 10) {
                        IconBadge(icon: e.kind == .income ? "arrow.down.circle" : "arrow.up.circle",
                                  tint: e.kind == .income ? Brand.green : Brand.red, size: 38, bgOpacity: 0.12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.kind == .income ? (snap.anyStudent(e.studentId)?.fullName ?? "اشتراك") : "صرف")
                                .font(T.titleSmall).foregroundColor(Brand.ink).lineLimit(1)
                            if let n = e.note, !n.isEmpty {
                                Text(n).font(T.bodySmall).foregroundColor(Brand.muted).fixedSize(horizontal: false, vertical: true)
                            }
                            Text(Days.parse(e.day).map { Fmt.date($0) } ?? e.day).font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                        Spacer(minLength: 4)
                        Text((e.kind == .income ? "+" : "−") + Money.yer(e.amount)).font(T.labelLarge)
                            .foregroundColor(e.kind == .income ? Brand.green : Brand.red)
                    }
                }
            }
        }
        .sheet(item: $adding) { k in BudgetEntrySheet(kind: k, entry: nil) }
        .sheet(item: $editing) { e in BudgetEntrySheet(kind: e.kind, entry: e) }
    }

    private func sumRow(_ title: String, _ v: Double, _ c: Color, big: Bool = false) -> some View {
        HStack {
            Text(title).font(big ? T.titleMedium : T.bodyMedium).foregroundColor(Brand.ink)
            Spacer()
            Text(Money.yer(v)).font(big ? T.titleLarge : T.titleSmall).foregroundColor(c)
        }
    }
}

extension BudgetKind: Identifiable { var id: String { rawValue } }

/// Add or edit one entry. Income: the student (its circle's fee fills the amount), amount, date, optional note.
/// Expense: amount, date and a REQUIRED note (his words, 10:00 PM: «ملاحظه عند اي عمليه صرف»).
struct BudgetEntrySheet: View {
    let kind: BudgetKind
    let entry: BudgetEntry?
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var note = ""
    @State private var date = Days.today
    @State private var studentId: String? = nil
    @State private var loaded = false

    var body: some View {
        let snap = model.snap
        let noteOk = kind == .income || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let ok = Money.parse(amount) != nil && noteOk && (kind == .expense || studentId != nil)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if kind == .income {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("الطالب").font(T.labelSmall).foregroundColor(Brand.muted)
                            Picker("الطالب", selection: $studentId) {
                                Text("اختر الطالب").tag(String?.none)
                                ForEach(snap.students.sorted { $0.fullName < $1.fullName }) { s in
                                    Text(s.fullName + (snap.circle(s.circleId).map { " • " + $0.name } ?? "")).tag(Optional(s.id))
                                }
                            }
                            .pickerStyle(.menu).tint(Brand.navy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.line, lineWidth: 1.2))
                            .accessibilityIdentifier("budgetStudent")
                        }
                    }
                    Field(label: "المبلغ (ريال يمني)", text: $amount, keyboard: .decimalPad)
                    VStack(alignment: .leading, spacing: 4) {
                        DatePicker("التاريخ", selection: $date, in: ...Date(), displayedComponents: .date)
                            .font(T.bodyLarge).tint(Brand.navy)
                    }
                    Field(label: kind == .expense ? "ملاحظة (مطلوبة): على ماذا صُرف المبلغ" : "ملاحظة (اختياري)", text: $note, multiline: true, minLines: 2)
                        .accessibilityIdentifier("budgetNote")
                    if kind == .expense && !noteOk {
                        Text("اكتب ملاحظة لعملية الصرف").font(T.labelSmall).foregroundColor(Brand.red)
                    }
                    PrimaryButton(title: "حفظ", enabled: ok) {
                        guard let v = Money.parse(amount) else { return }
                        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        var e = entry ?? BudgetEntry(id: "", kind: kind, amount: v, day: Days.iso(date))
                        e.kind = kind; e.amount = v; e.day = Days.iso(date)
                        e.studentId = kind == .income ? studentId : nil
                        e.note = n.isEmpty ? nil : n
                        let saved = e
                        model.run("تم الحفظ", { try await model.repo.saveBudgetEntry(saved) }) { _ in dismiss() }
                    }
                    .accessibilityIdentifier("saveBudgetEntry")
                    if let entry = entry {
                        OutlineButton(title: "حذف العملية") {
                            model.run("تم الحذف", { try await model.repo.deleteBudgetEntry(entry.id) }) { _ in dismiss() }
                        }
                    }
                }
                .padding(18)
            }
            .background(Brand.bg.ignoresSafeArea())
            .navigationTitle(entry == nil ? (kind == .income ? "دخل: اشتراك طالب" : "عملية صرف") : "تعديل العملية")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = entry {
                amount = e.amount == e.amount.rounded() ? String(Int(e.amount)) : String(e.amount)
                note = e.note ?? ""; studentId = e.studentId; date = Days.parse(e.day) ?? Days.today
            }
            #if DEBUG
            if entry == nil, kind == .expense, UserDefaults.standard.bool(forKey: "ciBudgetExpenseForm") { amount = "1500" }
            #endif
        }
        .onChange(of: studentId) { id in
            // the circle's fee fills the amount (still editable)
            guard entry == nil, let s = model.snap.student(id), let fee = model.snap.circle(s.circleId)?.feeYer, fee > 0 else { return }
            amount = String(fee)
        }
    }
}


// MARK: «كشف الاشتراكات» (student_subscriptions; files/alsiddiq_app/V38_ADMIN.md §4) — not linked to «الميزانية»

struct StudentSubscription: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var studentId: String
    /// the first day of the month, 'YYYY-MM-01'
    var month: String
    var paid: Bool
    var amount: Double? = nil
}

struct SubscriptionMark: Equatable {
    var paid: Bool
    var amount: Double?
}

extension Rows {
    static func subscription(_ o: JSON) -> StudentSubscription? {
        guard let id = o["id"] as? String, let sid = o["student_id"] as? String, let m = o["month"] as? String else { return nil }
        let amount: Double? = (o["amount"] as? NSNumber)?.doubleValue ?? (o["amount"] as? String).flatMap { Double($0) }
        let paid = (o["paid"] as? NSNumber)?.boolValue ?? false
        return StudentSubscription(id: id, studentId: sid, month: String(m.prefix(10)), paid: paid, amount: amount)
    }
}

enum Months {
    static func first(_ d: Date) -> Date { Days.cal.date(from: Days.cal.dateComponents([.year, .month], from: d)) ?? d }
    static func add(_ d: Date, _ n: Int) -> Date { Days.cal.date(byAdding: .month, value: n, to: first(d)) ?? d }
    private static let title: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar@numbers=latn"); f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "MMMM yyyy"; return f
    }()
    static func label(_ d: Date) -> String { title.string(from: d) }
}

/// The teacher sees his own circle(s); the admin every circle, or «كل الحلقات».
struct SubscriptionsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @State private var circleIdx = 0
    @State private var month = Months.first(Days.today)
    @State private var marks: [String: Bool] = [:]
    @State private var amounts: [String: String] = [:]
    @State private var loadedKey = ""

    var body: some View {
        let snap = model.snap
        let circles = Permissions.editableCircles(user, snap)
        let isAdmin = user.role == .admin
        let options = (isAdmin ? ["كل الحلقات"] : []) + circles.map { $0.name }
        let idx = min(circleIdx, max(options.count - 1, 0))
        let circle: StudyCircle? = isAdmin ? (idx == 0 ? nil : circles[safe: idx - 1]) : circles[safe: idx]
        let students = snap.students.filter { s in
            circle.map { s.circleId == $0.id } ?? (isAdmin || circles.contains { $0.id == s.circleId })
        }.sorted { $0.fullName < $1.fullName }
        let monthIso = Days.iso(month)
        var saved: [String: StudentSubscription] = [:]
        for x in (snap.subscriptions ?? []) where x.month == monthIso { saved[x.studentId] = x }
        let sig = saved.values.map { "\($0.studentId)=\($0.paid)/\($0.amount ?? -1)" }.sorted().joined(separator: ",")
        let key = "\(circle?.id ?? "all")|\(monthIso)|\(sig)"
        let paidIds = students.filter { marks[$0.id] == true }
        let total = paidIds.reduce(0.0) { $0 + (Money.parse(amounts[$1.id] ?? "") ?? 0) }
        let changed = changes(students, saved)
        let canForward = month < Months.first(Days.today)

        return ScreenList(title: "كشف الاشتراكات") {
            if options.count > 1 { ChoiceChips(options: options, selected: idx) { circleIdx = $0 } }
            AppCard(padding: 8) {
                HStack {
                    Button { month = Months.add(month, -1) } label: {
                        Image(systemName: "chevron.backward").font(.system(size: 17, weight: .semibold)).foregroundColor(Brand.ink).frame(width: 44, height: 44)
                    }.accessibilityLabel("الشهر السابق")
                    Spacer()
                    VStack(spacing: 1) {
                        Text(Months.label(month)).font(T.titleSmall).foregroundColor(Brand.ink)
                        Text("الاشتراك الشهري").font(T.labelSmall).foregroundColor(Brand.muted)
                    }
                    Spacer()
                    Button { if canForward { month = Months.add(month, 1) } } label: {
                        Image(systemName: "chevron.forward").font(.system(size: 17, weight: .semibold)).foregroundColor(canForward ? Brand.ink : Brand.line).frame(width: 44, height: 44)
                    }.disabled(!canForward).accessibilityLabel("الشهر التالي")
                }
            }
            HStack(spacing: 6) {
                Pill(text: "سلم \(paidIds.count)", color: Brand.green)
                Pill(text: "لم يسلم \(students.count - paidIds.count)", color: Brand.red)
                Pill(text: "المجموع " + Money.yerFull(total), color: Brand.navy)
                Spacer()
            }
            if students.isEmpty { EmptyState(title: "لا يوجد طلاب", message: "اختر حلقة فيها طلاب") }
            ForEach(students) { s in
                let isPaid = marks[s.id] == true
                AppCard(padding: 12) {
                    HStack(spacing: 10) {
                        Avatar(name: s.fullName, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.fullName).font(T.titleSmall).foregroundColor(Brand.ink)
                            if circle == nil, let c = snap.circle(s.circleId) { Text(c.name).font(T.labelSmall).foregroundColor(Brand.muted) }
                        }
                        Spacer()
                    }
                    Spacer().frame(height: 8)
                    HStack(spacing: 6) {
                        payButton("سلم", sel: isPaid, col: Brand.green) {
                            marks[s.id] = true
                            if (amounts[s.id] ?? "").isEmpty, let fee = snap.circle(s.circleId)?.feeYer, fee > 0 { amounts[s.id] = String(fee) }
                        }
                        payButton("لم يسلم", sel: !isPaid, col: Brand.red) { marks[s.id] = false }
                    }
                    if isPaid {
                        Spacer().frame(height: 8)
                        Field(label: "المبلغ (ريال يمني)", text: Binding(get: { amounts[s.id] ?? "" }, set: { amounts[s.id] = $0 }), keyboard: .decimalPad)
                    }
                }
                .accessibilityIdentifier("sub_" + s.id)
            }
            if !students.isEmpty {
                PrimaryButton(title: changed.isEmpty ? "محفوظ ✓" : "حفظ", enabled: !changed.isEmpty) {
                    let m = changed
                    model.run(nil, { try await model.repo.saveSubscriptions(month: monthIso, marks: m) }) { n in model.say("حُفظ اشتراك " + Fmt.students(n)) }
                }
                .accessibilityIdentifier("saveSubscriptions")
            }
        }
        .onAppear { sync(key, saved) }
        .onChange(of: key) { k in sync(k, saved) }
    }

    private func payButton(_ title: String, sel: Bool, col: Color, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeOut(duration: 0.12)) { action() } } label: {
            Text(title).font(T.labelMedium).foregroundColor(sel ? .white : col)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(sel ? col : col.opacity(0.08)))
        }
        .buttonStyle(PressableStyle())
    }

    /// Only what differs from the saved month is sent (a student with no row counts as «لم يسلم»).
    private func changes(_ students: [Student], _ saved: [String: StudentSubscription]) -> [String: SubscriptionMark] {
        var out: [String: SubscriptionMark] = [:]
        for s in students {
            let paid = marks[s.id] == true
            let amount = paid ? Money.parse(amounts[s.id] ?? "") : nil
            let was = saved[s.id]
            if paid != (was?.paid ?? false) || (paid && amount != was?.amount) { out[s.id] = SubscriptionMark(paid: paid, amount: amount) }
        }
        return out
    }

    private func sync(_ k: String, _ saved: [String: StudentSubscription]) {
        guard k != loadedKey else { return }
        loadedKey = k
        marks = saved.mapValues { $0.paid }
        amounts = saved.compactMapValues { $0.amount.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension Money {
    /// «٥٬٠٠٠ ريال يمني», like the fees.
    static func yerFull(_ v: Double) -> String { yer(v) + " يمني" }
}

// MARK: «لوحة الحلقة» (circles.photo_path; V38_ADMIN.md §3)

/// The circle's photo, loaded once (nil while loading or when there is none).
struct CirclePhotoImage<Fallback: View>: View {
    let circle: StudyCircle
    @ViewBuilder var fallback: () -> Fallback
    @EnvironmentObject var model: AppModel
    @State private var img: UIImage?
    var body: some View {
        Group {
            if let img = img { Image(uiImage: img).resizable().scaledToFill() } else { fallback() }
        }
        .task(id: circle.photoPath ?? "") { img = await model.repo.circlePhoto(circle) }
    }
}

/// The wide banner at the top of the circle page, with «تعديل اللوحة» for the admin and the circle's own teacher.
struct CircleBanner: View {
    let user: Member
    let circle: StudyCircle
    @EnvironmentObject var model: AppModel
    @State private var picker: PhotoSource?
    @State private var choosing = false
    var body: some View {
        let canEdit = Permissions.canTakeAttendance(user, circle.id, model.snap)
        VStack(alignment: .leading, spacing: 8) {
            if circle.photoPath != nil {
                Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay(CirclePhotoImage(circle: circle) { Brand.goldSoft })
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Brand.gold.opacity(0.45), lineWidth: 1))
                    .accessibilityIdentifier("circleBanner")
            }
            if canEdit {
                Button { choosing = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera").font(.system(size: 14, weight: .semibold))
                        Text(circle.photoPath == nil ? "إضافة لوحة الحلقة" : "تعديل اللوحة").font(T.labelLarge)
                    }
                    .foregroundColor(Brand.navy).padding(.horizontal, 12).frame(height: 34)
                    .background(Capsule().fill(Brand.navy.opacity(0.08)))
                }
                .accessibilityIdentifier("editCirclePhoto")
            }
        }
        .confirmationDialog("صورة الحلقة", isPresented: $choosing, titleVisibility: .visible) {
            Button("اختيار من الصور") { picker = .library }
            Button("الكاميرا") { picker = .camera }
            if circle.photoPath != nil {
                Button("حذف الصورة", role: .destructive) {
                    let id = circle.id
                    model.run("حُذفت صورة الحلقة", { try await model.repo.setCirclePhoto(circleId: id, jpeg: nil) })
                }
            }
            Button("إلغاء", role: .cancel) {}
        }
        .sheet(item: $picker) { src in
            PhotoPickerSheet(source: src) { img in
                picker = nil
                let id = circle.id
                // the bucket takes up to 300 KB: the widest size that fits
                if let img = img, let data = [1280, 1024, 800, 640].lazy.compactMap({ PhotoTools.jpeg(img, maxSide: CGFloat($0)) }).first(where: { $0.count <= 290_000 }) ?? PhotoTools.jpeg(img, maxSide: 512) {
                    model.run("تم حفظ لوحة الحلقة", { try await model.repo.setCirclePhoto(circleId: id, jpeg: data) })
                }
            }
            .ignoresSafeArea()
        }
    }
}


// MARK: «وسام الشرف لهذا الأسبوع» — automatic (his words 10:15 PM, «تلقائي»), computed on the phone, no server table.
// Per circle, this week (from Saturday): most ayat recited, then fewest absences, then the best average grade.

enum WeeklyStar {
    /// Saturday of this week (the week starts on Saturday).
    static func weekStart(_ d: Date = Days.today) -> Date {
        let wd = Days.cal.component(.weekday, from: d)   // 1 = Sunday … 7 = Saturday
        return Days.add(Days.dayOf(d), -((wd % 7)))
    }
    static func star(_ snap: CenterSnapshot, circleId: String) -> Student? {
        let since = weekStart()
        let sinceIso = Days.iso(since)
        let students = snap.studentsIn(circleId)
        let ids = Set(students.map { $0.id })
        let recs = snap.recitations.filter { ids.contains($0.studentId) && Days.dayOf($0.recordedAt) >= since }
        guard !recs.isEmpty else { return nil }
        var ayat: [String: Int] = [:], gsum: [String: Int] = [:], gn: [String: Int] = [:]
        for r in recs { ayat[r.studentId, default: 0] += Stats.ayatOf(r); gsum[r.studentId, default: 0] += r.grade.score; gn[r.studentId, default: 0] += 1 }
        var absent: [String: Int] = [:]
        for a in snap.attendance where ids.contains(a.studentId) && a.day >= sinceIso && a.status == .absent { absent[a.studentId, default: 0] += 1 }
        func grade(_ id: String) -> Double { (gn[id] ?? 0) > 0 ? Double(gsum[id] ?? 0) / Double(gn[id] ?? 1) : 0 }
        return students.filter { (ayat[$0.id] ?? 0) > 0 }.sorted { a, b in
            let (x, y) = (ayat[a.id] ?? 0, ayat[b.id] ?? 0)
            if x != y { return x > y }
            let (p, q) = (absent[a.id] ?? 0, absent[b.id] ?? 0)
            if p != q { return p < q }
            let (g, h) = (grade(a.id), grade(b.id))
            if g != h { return g > h }
            return a.fullName < b.fullName
        }.first
    }
}

/// On every home screen (the general view included): one row per circle.
struct WeeklyStarStrip: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        let circles = snap.circles.filter { $0.active }.sorted { $0.name < $1.name }
        if !circles.isEmpty {
            AppCard(padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        IconBadge(icon: "rosette", tint: Brand.gold, size: 34, art: "weekly_star")
                        VStack(alignment: .leading, spacing: 0) {
                            Text("وسام الشرف لهذا الأسبوع").font(T.titleSmall).foregroundColor(Brand.ink)
                            Text("تلقائياً: الأكثر حفظاً، ثم الأقل غياباً، ثم الأعلى تقديراً").font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                    }
                    ForEach(circles) { c in
                        let s = WeeklyStar.star(snap, circleId: c.id)
                        let teacher = snap.teacherName(of: c)
                        Button { if let s = s { router.go(.student(s.id)) } } label: {
                            HStack(spacing: 10) {
                                if let s = s { StudentAvatar(s: s, size: 38) }
                                else { IconBadge(icon: "rosette", tint: Brand.muted, size: 38, circle: true) }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("من حلقة " + (teacher.map { "الأستاذ " + $0 } ?? c.name)).font(T.labelMedium).foregroundColor(Brand.muted).lineLimit(1)
                                    Text(s.map { "الطالب " + $0.fullName } ?? "لم يُحدد بعد").font(T.titleSmall)
                                        .foregroundColor(s == nil ? Brand.muted : Brand.ink).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if s != nil { Text("🏅").font(.system(size: 20)) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .accessibilityIdentifier("weeklyStar")
        }
    }
}


/// «نجم الحلقة لهذا الأسبوع» inside a circle (its card and the top of its page).
struct CircleStarLine: View {
    let circleId: String
    var compact = false
    @EnvironmentObject var model: AppModel
    var body: some View {
        let s = WeeklyStar.star(model.snap, circleId: circleId)
        HStack(spacing: 8) {
            Text("🏅").font(.system(size: compact ? 15 : 20))
            Text("نجم الحلقة لهذا الأسبوع").font(compact ? T.labelSmall : T.labelLarge).foregroundColor(Brand.goldInk).lineLimit(1)
            Spacer(minLength: 4)
            if let s = s {
                Text(s.fullName).font(compact ? T.labelMedium : T.titleSmall).foregroundColor(Brand.ink).lineLimit(1)
                StudentAvatar(s: s, size: compact ? 24 : 34)
            } else {
                Text("لم يُحدد بعد").font(compact ? T.labelMedium : T.bodySmall).foregroundColor(Brand.muted)
            }
        }
        .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 5 : 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.goldSoft.opacity(0.7)))
        .accessibilityIdentifier("circleStar_" + circleId)
    }
}


// MARK: an announcement's photo (announcements.image_path; V38_ADMIN.md §8): full width, tap = full screen

struct AnnouncementPhoto: View {
    let path: String
    var maxHeight: CGFloat = 260
    @EnvironmentObject var model: AppModel
    @State private var img: UIImage?
    @State private var full = false
    var body: some View {
        Group {
            if let img = img {
                Button { full = true } label: {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: min(maxHeight, 220))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.line.opacity(0.5)).frame(height: 120)
                    .overlay(ProgressView())
            }
        }
        .task(id: path) { img = await model.repo.announcementImage(path) }
        .fullScreenCover(isPresented: $full) {
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                if let img = img { Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
                Button { full = false } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .frame(width: 44, height: 44).background(SwiftUI.Circle().fill(Color.white.opacity(0.18)))
                }
                .padding(16)
            }
        }
    }
}
