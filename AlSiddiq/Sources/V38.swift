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
