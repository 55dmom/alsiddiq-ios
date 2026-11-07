import SwiftUI

/// Steps 1–2 of the teacher flow: pick the circle, then the student.
struct RecordStartScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var circleIdx = 0
    var body: some View {
        let snap = model.snap
        let circles = Permissions.visibleCircles(user, snap)
        let circle = circles.indices.contains(circleIdx) ? circles[circleIdx] : nil
        let students = circle.map { c in snap.studentsIn(c.id).sorted { $0.fullName < $1.fullName } } ?? []
        let logged = Set(snap.recitations.filter { Days.dayOf($0.recordedAt) == Days.today }.map { $0.studentId })
        ScreenList(title: "تسجيل تسميع") {
            Text("١. اختر الحلقة").font(T.labelLarge).foregroundColor(Brand.muted)
            ChoiceChips(options: circles.map { $0.name }, selected: circleIdx) { circleIdx = $0 }
            HStack {
                Text("٢. اختر الطالب").font(T.labelLarge).foregroundColor(Brand.muted)
                Spacer()
                Text("سُجّل اليوم \(students.filter { logged.contains($0.id) }.count)/\(students.count)").font(T.labelMedium).foregroundColor(Brand.green)
            }
            if circles.isEmpty { EmptyState(title: "لا توجد حلقات", message: "لم تُسند إليك حلقة بعد") }
            else if students.isEmpty { EmptyState(title: "لا يوجد طلاب", message: "هذه الحلقة بلا طلاب بعد") }
            ForEach(students) { s in
                StudentRow(s: s, snap: snap, onTap: { router.go(.record(s.id)) }) {
                    if logged.contains(s.id) { Pill(text: "✓ اليوم", color: Brand.green) }
                    else { Image(systemName: "plus.circle").font(.system(size: 20)).foregroundColor(Brand.maroon) }
                }
            }
        }
    }
}

/// Steps 3–5: surah + ayat, grade, save. Stats update immediately after saving.
struct RecordScreen: View {
    let user: Member
    let studentId: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var dialogs: DialogHost
    @State private var loaded = false
    @State private var kind: RecordKind = .hifz
    @State private var fromSurah = 1
    @State private var fromAyah = "1"
    @State private var toSurah = 1
    @State private var toAyah = "5"
    @State private var grade: Grade?
    @State private var mistakes = 0
    @State private var notes = ""
    @State private var saving = false

    private func lastHifz(_ snap: CenterSnapshot) -> Recitation? {
        snap.recitations.filter { $0.studentId == studentId && $0.kind == .hifz }.max { $0.recordedAt < $1.recordedAt }
    }

    private func rangeMessage(_ fa: Int, _ ta: Int, _ ayat: Int) -> String? {
        if !Quran.isValid(fromSurah, fa) { return "رقم آية البداية غير صحيح (السورة \(Quran.ayahCount(fromSurah)) آية)" }
        if !Quran.isValid(toSurah, ta) { return "رقم آية النهاية غير صحيح (السورة \(Quran.ayahCount(toSurah)) آية)" }
        if ayat <= 0 { return "نهاية المقطع قبل بدايته" }
        return nil
    }

    private func surahLabel(_ n: Int) -> String { "\(n). \(Quran.name(n)) (\(Quran.ayahCount(n)))" }

    var body: some View {
        let snap = model.snap
        if let s = snap.student(studentId) {
            form(s, snap)
        } else {
            ScreenList(title: "تسجيل") { EmptyState(title: "الطالب غير موجود", message: "") }
        }
    }

    private func form(_ s: Student, _ snap: CenterSnapshot) -> some View {
        let fa = Int(fromAyah) ?? 0
        let ta = Int(toAyah) ?? 0
        let ayat = Quran.ayatBetween(fromSurah, fa, toSurah, ta)
        let valid = ayat > 0 && grade != nil
        let pages = ayat > 0 ? Quran.pagesOf(Quran.globalIndex(fromSurah, fa), Quran.globalIndex(toSurah, ta)) : 0
        let circleStudents = snap.studentsIn(s.circleId).sorted { $0.fullName < $1.fullName }
        let loggedToday = Set(snap.recitations.filter { Days.dayOf($0.recordedAt) == Days.today }.map { $0.studentId })
        let next = circleStudents.first { $0.id != s.id && !loggedToday.contains($0.id) }
        let last = lastHifz(snap)
        let msg = rangeMessage(fa, ta, ayat)

        func save(goNext: Bool) {
            guard let g = grade else { return }
            saving = true
            let r = Recitation(id: "", studentId: s.id, circleId: s.circleId, teacherId: user.id, kind: kind, fromSurah: fromSurah, fromAyah: fa,
                               toSurah: toSurah, toAyah: ta, grade: g, mistakes: mistakes, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
            model.run("حُفظ: \(kind.label) \(ayat) آية — \(g.label)", { try await model.repo.logRecitation(r) }, onError: { saving = false }) { _ in
                saving = false
                if goNext, let n = next { router.replaceTop(.record(n.id)) } else { router.back() }
            }
        }

        return ScreenList(title: "تسجيل لـ \(s.fullName)") {
            AppCard(padding: 12, onTap: { router.go(.student(s.id)) }) {
                HStack(spacing: 10) {
                    Avatar(name: s.fullName)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.fullName).font(T.titleSmall).foregroundColor(Brand.ink)
                        Text("آخر حفظ: " + (last.map { Stats.describeRange($0) + " • " + Fmt.relative($0.recordedAt) } ?? "لا يوجد"))
                            .font(T.bodySmall).foregroundColor(Brand.muted)
                    }
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis").foregroundColor(Brand.navy)
                }
            }
            Text("نوع التسجيل").font(T.labelLarge).foregroundColor(Brand.muted)
            SegmentedRow(options: RecordKind.allCases.map { $0.label }, selected: RecordKind.allCases.firstIndex(of: kind) ?? 0,
                         colors: RecordKind.allCases.map { kindColor($0) }) { kind = RecordKind.allCases[$0] }
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("المقطع").font(T.titleSmall).foregroundColor(Brand.ink)
                    Text("من").font(T.labelMedium).foregroundColor(Brand.muted)
                    HStack(alignment: .bottom, spacing: 8) {
                        SelectorField(label: "السورة", value: Quran.name(fromSurah)) {
                            dialogs.show(PickerDialog(title: "سورة البداية", items: Array(1...114), label: surahLabel, searchable: true) { n in
                                fromSurah = n; fromAyah = "1"
                                if toSurah < n { toSurah = n; toAyah = String(min(Quran.ayahCount(n), 5)) }
                            })
                        }
                        .layoutPriority(1.6)
                        Field(label: "الآية", text: Binding(get: { fromAyah }, set: { v in fromAyah = String(v.filter { $0.isNumber }.prefix(3)) }), keyboard: .numberPad)
                            .frame(width: 96)
                    }
                    Text("إلى").font(T.labelMedium).foregroundColor(Brand.muted).padding(.top, 2)
                    HStack(alignment: .bottom, spacing: 8) {
                        SelectorField(label: "السورة", value: Quran.name(toSurah)) {
                            dialogs.show(PickerDialog(title: "سورة النهاية", items: Array(1...114), label: surahLabel, searchable: true) { n in
                                toSurah = n; toAyah = String(Quran.ayahCount(n))
                            })
                        }
                        .layoutPriority(1.6)
                        Field(label: "الآية", text: Binding(get: { toAyah }, set: { v in toAyah = String(v.filter { $0.isNumber }.prefix(3)) }), keyboard: .numberPad)
                            .frame(width: 96)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            AssistChip(title: "حتى نهاية السورة") { toSurah = fromSurah; toAyah = String(Quran.ayahCount(fromSurah)) }
                            AssistChip(title: "السورة كاملة") { fromAyah = "1"; toSurah = fromSurah; toAyah = String(Quran.ayahCount(fromSurah)) }
                            AssistChip(title: "+5 آيات") {
                                let base = Int(toAyah) ?? fa
                                toSurah = fromSurah; toAyah = String(min(base + 5, Quran.ayahCount(fromSurah)))
                            }
                        }
                    }
                    .padding(.top, 2)
                    if let m = msg {
                        Text(m).font(T.bodySmall).foregroundColor(Brand.red)
                    } else {
                        HStack(spacing: 6) {
                            Pill(text: "\(ayat) آية", color: Brand.navy)
                            Pill(text: "\(Fmt.one(pages)) صفحة", color: Brand.maroon)
                            Pill(text: "الجزء \(Quran.juzOf(fromSurah, fa))", color: Brand.gold)
                        }
                    }
                }
            }
            Text("التقدير").font(T.labelLarge).foregroundColor(Brand.muted)
            HStack(spacing: 6) {
                ForEach(Grade.allCases) { g in
                    let sel = grade == g
                    Button { withAnimation(.easeOut(duration: 0.15)) { grade = g } } label: {
                        Text(g.label).font(T.labelMedium).foregroundColor(sel ? .white : gradeColor(g))
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(sel ? gradeColor(g) : gradeColor(g).opacity(0.08)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            AppCard(padding: 12) {
                HStack(spacing: 0) {
                    Text("عدد الأخطاء").font(T.bodyMedium).foregroundColor(Brand.ink)
                    Spacer()
                    RoundIconButton(icon: "minus") { if mistakes > 0 { mistakes -= 1 } }
                    Text("\(mistakes)").font(T.titleLarge).foregroundColor(Brand.ink).frame(minWidth: 44)
                    RoundIconButton(icon: "plus") { mistakes += 1 }
                }
                Spacer().frame(height: 8)
                Field(label: "ملاحظة للطالب وولي الأمر (اختياري)", text: $notes, multiline: true, minLines: 2)
            }
            PrimaryButton(title: grade == nil ? "اختر التقدير للحفظ" : "حفظ النتيجة", icon: "checkmark", enabled: valid && !saving, height: 54) { save(goNext: false) }
            if let n = next {
                OutlineButton(title: "حفظ والانتقال إلى \(n.fullName)", enabled: valid && !saving) { save(goNext: true) }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            // Suggest continuing right after the last memorised ayah.
            var start = (1, 1)
            if let l = last {
                if l.toAyah < Quran.ayahCount(l.toSurah) { start = (l.toSurah, l.toAyah + 1) }
                else if l.toSurah < 114 { start = (l.toSurah + 1, 1) }
            }
            fromSurah = start.0; fromAyah = String(start.1)
            toSurah = start.0; toAyah = String(min(start.1 + 4, Quran.ayahCount(start.0)))
        }
    }
}

struct SegmentedRow: View {
    let options: [String]
    let selected: Int
    var colors: [Color]? = nil
    let onSelect: (Int) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                let sel = i == selected
                let c = colors?[i] ?? Brand.navy
                Button { withAnimation(.easeOut(duration: 0.18)) { onSelect(i) } } label: {
                    HStack(spacing: 4) {
                        if sel { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                        Text(o).font(T.labelLarge)
                    }
                    .foregroundColor(sel ? c : Brand.ink)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(sel ? c.opacity(0.15) : Color.white)
                }
                if i < options.count - 1 { Rectangle().fill(Brand.line).frame(width: 1, height: 42) }
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Brand.line, lineWidth: 1.2))
    }
}

struct RoundIconButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundColor(Brand.navy)
                .frame(width: 40, height: 40).background(SwiftUI.Circle().fill(Brand.navySoft))
        }
        .buttonStyle(PressableStyle())
    }
}
