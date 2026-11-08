import SwiftUI

// MARK: - v3.7 «المتفوقون»: ranked automatically by the same score as «التقارير» (new memorisation, in ayat)

enum HonorPeriod: Int, CaseIterable {
    case month, term, all
    var label: String { switch self { case .month: return "الشهر"; case .term: return "الفصل"; case .all: return "الكل" } }
    /// The first day counted (nil = everything). الشهر = last 30 days, الفصل = last 90 days, like the reports' ranges.
    var since: Date? {
        switch self {
        case .month: return Days.add(Days.today, -29)
        case .term: return Days.add(Days.today, -89)
        case .all: return nil
        }
    }
}

struct HonorRank: Identifiable {
    let student: Student
    let ayat: Int
    let grade: Double
    var id: String { student.id }
}

enum Honors {
    /// Students ranked by new memorisation (ayat) in the period, then by average grade; students with nothing are left out.
    static func rank(_ snap: CenterSnapshot, period: HonorPeriod, circleId: String? = nil) -> [HonorRank] {
        let since = period.since
        let students = snap.students.filter { circleId == nil || $0.circleId == circleId }
        let ids = Set(students.map { $0.id })
        let recs = snap.recitations.filter { ids.contains($0.studentId) && (since == nil || Days.dayOf($0.recordedAt) >= since!) }
        var ayat: [String: Int] = [:], gsum: [String: Int] = [:], gn: [String: Int] = [:]
        for r in recs {
            if r.kind == .hifz { ayat[r.studentId, default: 0] += Stats.ayatOf(r) }
            gsum[r.studentId, default: 0] += r.grade.score; gn[r.studentId, default: 0] += 1
        }
        return students.compactMap { s -> HonorRank? in
            let a = ayat[s.id] ?? 0
            guard a > 0 else { return nil }
            let g = (gn[s.id] ?? 0) > 0 ? Double(gsum[s.id] ?? 0) / Double(gn[s.id] ?? 1) : 0
            return HonorRank(student: s, ayat: a, grade: g)
        }
        .sorted { ($0.ayat, $0.grade, $1.student.fullName) > ($1.ayat, $1.grade, $0.student.fullName) }
    }

    static func scoreText(_ r: HonorRank) -> String { "\(r.ayat) آية حفظ" }

    static func entry(_ r: HonorRank, _ snap: CenterSnapshot) -> HonorStudent {
        HonorStudent(id: r.student.id, fullName: r.student.fullName, photoPath: r.student.photoPath,
                     circleName: snap.circle(r.student.circleId)?.name, scoreText: scoreText(r))
    }

    static func medal(_ i: Int) -> String? { i == 0 ? "🥇" : (i == 1 ? "🥈" : (i == 2 ? "🥉" : nil)) }

    // shown once per phone
    static let seenKey = "honorCardSeen"
    static func unseen(_ snap: CenterSnapshot) -> HonorCard? {
        guard let c = snap.honors.first, !c.students.isEmpty else { return nil }
        return UserDefaults.standard.string(forKey: seenKey) == c.id ? nil : c
    }
    static func markSeen(_ c: HonorCard) { UserDefaults.standard.set(c.id, forKey: seenKey) }
}

/// A photo for an honoured student (or an event's snapshot): the live row's photo when it exists.
struct HonorAvatar: View {
    let id: String
    let name: String
    let photoPath: String?
    var size: CGFloat = 44
    @EnvironmentObject var model: AppModel
    var body: some View {
        StudentAvatar(s: model.snap.anyStudent(id) ?? Student(id: id, fullName: name, circleId: nil, joinedOn: "", photoPath: photoPath), size: size)
    }
}

struct HonorRow: View {
    let index: Int
    let r: HonorRank
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        AppCard(padding: 12, onTap: { router.go(.student(r.student.id)) }) {
            HStack(spacing: 12) {
                Text(Honors.medal(index) ?? "\(index + 1)").font(index < 3 ? .system(size: 26) : T.titleMedium)
                    .foregroundColor(Brand.muted).frame(width: 34)
                StudentAvatar(s: r.student, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.student.fullName).font(T.titleSmall).foregroundColor(Brand.ink).lineLimit(1)
                    Text(model.snap.circle(r.student.circleId)?.name ?? "").font(T.bodySmall).foregroundColor(Brand.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Honors.scoreText(r)).font(T.labelLarge).foregroundColor(Brand.navy)
            }
        }
    }
}

struct HonorsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var period = 0
    var body: some View {
        let snap = model.snap
        let p = HonorPeriod(rawValue: period) ?? .month
        let centre = Honors.rank(snap, period: p)
        ScreenList(title: "المتفوقون") {
            SegmentedRow(options: HonorPeriod.allCases.map { $0.label }, selected: period) { period = $0 }
            if user.role == .admin {
                PrimaryButton(title: "اظهر تفوق الطالب") { router.go(.honorPublish) }
                    .accessibilityIdentifier("honorPublishButton")
            }
            if let c = snap.honors.first {
                AppCard {
                    HStack(spacing: 8) {
                        Text("🏆").font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("آخر تهنئة من الإدارة").font(T.titleSmall).foregroundColor(Brand.ink)
                            Text(Fmt.relative(c.createdAt)).font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                    }
                    Text(c.students.map { $0.fullName }.joined(separator: "، ")).font(T.bodyMedium).foregroundColor(Brand.navy).padding(.top, 6)
                    if let m = c.message, !m.isEmpty { Text(m).font(T.bodySmall).foregroundColor(Brand.muted).padding(.top, 4) }
                }
            }
            SectionHeader(title: "المركز كاملاً")
            if centre.isEmpty { EmptyState(title: "لا يوجد حفظ جديد في هذه الفترة", message: "يظهر المتفوقون هنا تلقائياً من سجلات الحفظ") }
            ForEach(Array(centre.prefix(10).enumerated()), id: \.element.id) { i, r in HonorRow(index: i, r: r) }
            ForEach(Permissions.visibleCircles(user, snap)) { c in
                let list = Honors.rank(snap, period: p, circleId: c.id)
                if !list.isEmpty {
                    SectionHeader(title: c.name)
                    ForEach(Array(list.prefix(3).enumerated()), id: \.element.id) { i, r in HonorRow(index: i, r: r) }
                }
            }
        }
    }
}

/// Admin: «اظهر تفوق الطالب» — the top 3 are picked already (editable), an optional message, then publish.
struct HonorPublishScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var period = 0
    @State private var picked: [String] = []
    @State private var message = ""
    @State private var loaded = false
    var body: some View {
        let snap = model.snap
        let ranked = Honors.rank(snap, period: HonorPeriod(rawValue: period) ?? .month)
        ScreenList(title: "اظهر تفوق الطالب") {
            SegmentedRow(options: HonorPeriod.allCases.map { $0.label }, selected: period) { period = $0; picked = Array(Honors.rank(snap, period: HonorPeriod(rawValue: $0) ?? .month).prefix(3).map { $0.id }) }
            Text("اختر الطلاب (الثلاثة الأوائل مختارون)").font(T.bodySmall).foregroundColor(Brand.muted)
            if ranked.isEmpty { EmptyState(title: "لا يوجد حفظ جديد في هذه الفترة", message: "جرّب «الفصل» أو «الكل»") }
            ForEach(Array(ranked.prefix(30).enumerated()), id: \.element.id) { i, r in
                let on = picked.contains(r.id)
                AppCard(padding: 12, onTap: { if on { picked.removeAll { $0 == r.id } } else { picked.append(r.id) } }) {
                    HStack(spacing: 12) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundColor(on ? Brand.green : Brand.muted)
                        Text(Honors.medal(i) ?? "\(i + 1)").font(i < 3 ? .system(size: 22) : T.labelLarge).frame(width: 28)
                        StudentAvatar(s: r.student, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.student.fullName).font(T.titleSmall).foregroundColor(Brand.ink).lineLimit(1)
                            Text(snap.circle(r.student.circleId)?.name ?? "").font(T.bodySmall).foregroundColor(Brand.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(Honors.scoreText(r)).font(T.labelMedium).foregroundColor(Brand.navy)
                    }
                }
            }
            Field(label: "رسالة التهنئة (اختياري)", text: $message, multiline: true, minLines: 2)
            PrimaryButton(title: "اظهر تفوق الطالب") {
                let list = ranked.filter { picked.contains($0.id) }.map { Honors.entry($0, snap) }
                model.run("نُشرت التهنئة", { try await model.repo.publishHonors(list, message: message) }) { _ in router.back() }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            picked = Array(ranked.prefix(3).map { $0.id })
        }
    }
}

/// The once-only full-screen congratulation after a new card is published (the occasion greeting's look).
struct HonorGreeting: View {
    let card: HonorCard
    let onClose: () -> Void
    @State private var shine = false
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    SwiftUI.Circle().fill(Brand.gold.opacity(shine ? 0.5 : 0.22)).frame(width: 120, height: 120).blur(radius: 18)
                    Text("🏆").font(.system(size: 58))
                }
                .frame(height: 110)
                Text("مبارك للمتفوقين").font(T.headlineSmall).foregroundColor(.white).multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    ForEach(card.students.prefix(6)) { h in
                        HStack(spacing: 10) {
                            HonorAvatar(id: h.id, name: h.fullName, photoPath: h.photoPath, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.fullName).font(T.titleSmall).foregroundColor(.white).lineLimit(1)
                                Text([h.circleName, h.scoreText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "))
                                    .font(T.bodySmall).foregroundColor(.white.opacity(0.75)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if card.students.count > 6 {
                        Text("و\(card.students.count - 6) آخرون").font(T.bodySmall).foregroundColor(.white.opacity(0.75))
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.08)))
                Text("شكراً لكم على تميّزكم").font(T.titleMedium).foregroundColor(Brand.gold)
                if let m = card.message, !m.isEmpty {
                    Text(m).font(T.bodyMedium).foregroundColor(.white.opacity(0.88)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: onClose) {
                    Text("شكراً").font(T.titleMedium).foregroundColor(Brand.navyDark)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Capsule().fill(Brand.gold))
                }
                .padding(.top, 4)
                .accessibilityIdentifier("honorThanks")
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.navy, Brand.navyDark], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Brand.gold.opacity(0.8), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 22)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { shine = true } }
        .accessibilityIdentifier("honorGreeting")
    }
}

/// Home card: the current top 3 this month, tap for the whole list.
struct HonorsHomeCard: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let top = Honors.rank(model.snap, period: .month).prefix(3)
        AppCard(onTap: { router.go(.honors) }) {
            HStack {
                Text("🏆 المتفوقون").font(T.titleSmall).foregroundColor(Brand.ink)
                Spacer()
                Text("الكل").font(T.labelLarge).foregroundColor(Brand.navy)
                Image(systemName: "chevron.backward").font(.system(size: 12, weight: .semibold)).foregroundColor(Brand.navy)
            }
            if top.isEmpty {
                Text("يظهرون هنا تلقائياً من سجلات الحفظ").font(T.bodySmall).foregroundColor(Brand.muted).padding(.top, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { i, r in
                        HStack(spacing: 10) {
                            Text(Honors.medal(i) ?? "").font(.system(size: 20))
                            StudentAvatar(s: r.student, size: 32)
                            Text(r.student.fullName).font(T.bodyMedium).foregroundColor(Brand.ink).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Honors.scoreText(r)).font(T.labelMedium).foregroundColor(Brand.navy)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - v3.6 the admin's bell

struct AdminEventsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        let list = snap.events
        ScreenList(title: "نشاط المعلمين", actions: {
            if list.contains(where: { $0.readAt == nil }) {
                TextAction(title: "قراءة الكل", color: Brand.navy) { model.run("تم تعليم الكل كمقروء", { try await model.repo.markAllEventsRead() }) }
            }
        }) {
            if list.isEmpty { EmptyState(title: "لا يوجد نشاط بعد", message: "يظهر هنا كل طالب يسجّله معلم أو يفصله") }
            ForEach(list) { e in
                AppCard(padding: 12, onTap: {
                    if e.readAt == nil { model.run(nil, { try await model.repo.markEventRead(e.id) }) }
                    router.go(.adminEvent(e.id))
                }) {
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            SwiftUI.Circle().fill((e.added ? Brand.green : Brand.red).opacity(e.readAt == nil ? 0.16 : 0.08))
                            Image(systemName: e.added ? "person.badge.plus" : "person.badge.minus").font(.system(size: 17))
                                .foregroundColor(e.added ? Brand.green : Brand.red)
                        }.frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.line).font(AppFont.f(14, e.readAt == nil ? .bold : .medium)).foregroundColor(Brand.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if let c = e.circleName, !c.isEmpty { Text(c).font(T.bodySmall).foregroundColor(Brand.muted) }
                            Text(Fmt.relative(e.createdAt)).font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                        Spacer()
                        if e.readAt == nil { SwiftUI.Circle().fill(Brand.maroon).frame(width: 9, height: 9).padding(.top, 6) }
                    }
                }
            }
            if !snap.notifications.isEmpty {
                MenuRow(title: "الإشعارات الأخرى", sub: "\(snap.notifications.count) إشعار", icon: "bell") { router.go(.notifications) }
            }
        }
    }
}

/// Tap on an event: the student's information as it was then, and his live file when he is still in a circle.
struct AdminEventScreen: View {
    let user: Member
    let id: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        if let e = snap.events.first(where: { $0.id == id }) {
            ScreenList(title: e.added ? "طالب جديد" : "طالب مفصول") {
                AppCard {
                    HStack(spacing: 12) {
                        HonorAvatar(id: e.studentId ?? "", name: e.fullName, photoPath: e.photoPath, size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.fullName).font(T.titleLarge).foregroundColor(Brand.ink)
                            Pill(text: e.added ? "سجّله " + e.actorName : "فصله " + e.actorName, color: e.added ? Brand.green : Brand.red)
                            Text(Fmt.relative(e.createdAt)).font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                    }
                }
                AppCard {
                    KeyValueRow(key: "الحلقة", value: e.circleName ?? "—")
                    if let t = e.teacherName, !t.isEmpty { KeyValueRow(key: "المعلم", value: t) }
                    if let l = e.level, !l.isEmpty { KeyValueRow(key: "المستوى", value: Fmt.level(l)) }
                    if let p = e.phone, !p.isEmpty { KeyValueRow(key: "الجوال", value: p) }
                    if let b = e.birthYear { KeyValueRow(key: "سنة الميلاد", value: String(b)) }
                    if let j = e.joinedOn, !j.isEmpty { KeyValueRow(key: "تاريخ الالتحاق", value: j) }
                    if let g = e.goalJuz { KeyValueRow(key: "الهدف", value: "\(g) أجزاء") }
                    if let n = e.notes, !n.isEmpty { KeyValueRow(key: "ملاحظات", value: n) }
                }
                if let sid = e.studentId, snap.student(sid) != nil {
                    PrimaryButton(title: "فتح ملف الطالب") { router.go(.student(sid)) }
                } else if !e.added {
                    Text("الطالب مفصول ولا يظهر في القوائم.").font(T.bodySmall).foregroundColor(Brand.muted)
                }
            }
            .onAppear { if e.readAt == nil { model.run(nil, { try await model.repo.markEventRead(e.id) }) } }
        } else {
            ScreenList(title: "النشاط") { EmptyState(title: "غير موجود", message: "ربما حُدّثت القائمة") }
        }
    }
}
