import SwiftUI

// ======================= v3: general view, Settings with «الإدارة» and «المعلمين», passwords, teacher names, reports =======================

/// Shown at the top of the admin and teachers sections: which section is open, and the way back to the general view.
struct RoleStrip: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: user.role == .admin ? "lock.shield" : "person.2.badge.gearshape").foregroundColor(Brand.goldInk)
            Text(user.role == .admin ? "أنت في قسم الإدارة" : "أنت في قسم المعلمين").font(T.labelLarge).foregroundColor(Brand.ink)
            Spacer()
            Button {
                Task { await model.repo.leaveRole(); model.pull() }
            } label: {
                HStack(spacing: 4) { Image(systemName: "rectangle.portrait.and.arrow.right"); Text("خروج") }
                    .font(T.labelLarge).foregroundColor(Brand.maroon)
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(Capsule().fill(Brand.maroonSoft))
            }
            .accessibilityIdentifier("leaveRole")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.goldSoft))
    }
}

/// Home for the general (read-only) password: the whole centre at a glance.
struct ViewerHome: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router

    var body: some View {
        let snap = model.snap
        let stats = Stats.forCenter(snap, snap.students)
        let per: [(Student, StudentStats)] = snap.students.map { ($0, Stats.forStudent($0, snap)) }.sorted { $0.1.memorisedAyat > $1.1.memorisedAyat }
        let totalJuz = per.reduce(0.0) { $0 + $1.1.juzEquivalent }
        let today = Days.today
        let reports = Array(snap.announcements.sorted { $0.createdAt > $1.createdAt }.prefix(3))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeader(greeting: "السلام عليكم ورحمة الله", title: snap.center.name.isEmpty ? model.centerName : snap.center.name,
                           subtitle: "\(Fmt.dayTitle(today)) • \(Fmt.hijri(today))", unread: snap.unreadCount) { router.go(.announcements) }
                VStack(alignment: .leading, spacing: 0) {
                    if model.isDemo { DemoBanner().padding(.top, 12) }
                    HStack(spacing: 8) {
                        Image(systemName: "eye").foregroundColor(Brand.gold)
                        Text("وضع العرض: تصفّح فقط. التعديل من الإعدادات ← الإدارة أو المعلمين").font(T.bodySmall).foregroundColor(Brand.ink)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.goldSoft))
                    .padding(.top, 12)
                    .accessibilityIdentifier("viewerBanner")
                    HStack(spacing: 10) {
                        StatTile(label: "الطلاب", value: "\(stats.students)", icon: "graduationcap", tint: Brand.navy) { router.go(.students) }
                        StatTile(label: "الحلقات", value: "\(snap.circles.count)", icon: "person.3", tint: Brand.maroon) { router.go(.circles) }
                        StatTile(label: "المعلمون", value: "\(snap.teachers().count)", icon: "person.crop.rectangle", tint: Brand.gold)
                    }.padding(.top, 10)
                    HStack(spacing: 10) {
                        StatTile(label: "المحفوظ (أجزاء)", value: Fmt.one(totalJuz), icon: "book.closed", tint: Brand.green, sub: "لكل الطلاب")
                        StatTile(label: "آيات الأسبوع", value: "\(stats.ayatThisWeek)", icon: "book", tint: Brand.navy)
                        StatTile(label: "حضور اليوم", value: stats.attendanceToday > 0 ? Fmt.pct(stats.attendanceToday) : "—", icon: "checklist", tint: Brand.maroon)
                    }.padding(.top, 10)
                    SectionHeader(title: "التفاعل", action: "التقارير") { router.go(.reports) }
                    AppCard {
                        Text("عدد السجلات يومياً — آخر 14 يوماً").font(T.bodySmall).foregroundColor(Brand.muted)
                        Spacer().frame(height: 10)
                        BarChart(data: stats.dailyRecords.map { BarDatum(label: Fmt.shortDay($0.0) + " \(Days.dayOfMonth($0.0))", value: Double($0.1), detail: "\($0.1) سجل") })
                    }
                    SectionHeader(title: "كم حفظ كل طالب", action: "كل الطلاب") { router.go(.students) }
                    if per.isEmpty { EmptyState(title: "لا يوجد طلاب بعد", message: "تضيفهم الإدارة أو المعلمون") }
                    VStack(spacing: 8) {
                        ForEach(per.prefix(10), id: \.0.id) { pair in
                            AppCard(padding: 12, onTap: { router.go(.student(pair.0.id)) }) {
                                HStack(spacing: 10) {
                                    StudentAvatar(s: pair.0, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pair.0.fullName).font(T.titleSmall).foregroundColor(Brand.ink)
                                        Text(snap.circle(pair.0.circleId)?.name ?? "بدون حلقة").font(T.labelSmall).foregroundColor(Brand.muted)
                                        LinearMeter(progress: pair.1.juzEquivalent / 30, color: Brand.gold).padding(.top, 3)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("\(Fmt.one(pair.1.juzEquivalent)) جزء").font(T.labelLarge).foregroundColor(Brand.navy)
                                        Text("\(pair.1.memorisedAyat) آية").font(T.labelSmall).foregroundColor(Brand.muted)
                                    }
                                }
                            }
                        }
                    }
                    SectionHeader(title: "الحلقات", action: "عرض الكل") { router.go(.circles) }
                    VStack(spacing: 10) {
                        ForEach(snap.circles.sorted { $0.name < $1.name }) { c in CircleCard(c: c, snap: snap) { router.go(.circle(c.id)) } }
                    }
                    SectionHeader(title: "آخر التقارير", action: "الكل") { router.go(.announcements) }
                    if reports.isEmpty { EmptyState(title: "لا توجد تقارير بعد", message: "تظهر هنا تقارير المعلمين اليومية وإعلانات المركز") }
                    VStack(spacing: 8) {
                        ForEach(reports) { a in
                            AppCard(padding: 12) {
                                Text(a.title).font(T.titleSmall).foregroundColor(Brand.ink)
                                Text(a.body).font(T.bodySmall).foregroundColor(Brand.muted).lineLimit(4).padding(.top, 4)
                                Text(Fmt.relative(a.createdAt)).font(T.labelSmall).foregroundColor(Brand.muted).padding(.top, 4)
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

private struct BigSectionButton: View {
    let title: String
    let sub: String
    let icon: String
    let color: Color
    let id: String
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 58, height: 58).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.16)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(T.headlineSmall).foregroundColor(.white)
                    Text(sub).font(T.bodySmall).foregroundColor(.white.opacity(0.85)).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "lock.fill").foregroundColor(Brand.gold)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient(colors: [color, color.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Brand.gold.opacity(0.45), lineWidth: 1))
            .shadow(color: color.opacity(0.25), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(id)
    }
}

/// The general view's Settings: two big buttons, each with its own password screen.
struct ViewerSettingsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var dialogs: DialogHost
    var body: some View {
        ScreenList(title: "الإعدادات") {
            BigSectionButton(title: "الإدارة", sub: "كلمة سر الإدارة: التحكم الكامل في التطبيق", icon: "lock.shield.fill", color: Brand.navy, id: "btnAdmin") {
                router.go(.roleLogin(.admin))
            }
            BigSectionButton(title: "المعلمين", sub: "كلمة سر المعلمين: الحلقات والطلاب والتسميع والحضور", icon: "person.2.fill", color: Brand.maroon, id: "btnTeachers") {
                router.go(.roleLogin(.teacher))
            }
            SectionHeader(title: "عام")
            MenuRow(title: "الإعلانات والتقارير", sub: "إعلانات المركز وتقارير الحلقات", icon: "megaphone") { router.go(.announcements) }
            MenuRow(title: "عن التطبيق", sub: "الإصدار وحالة المزامنة", icon: "info.circle") { router.go(.about) }
            MenuRow(title: "قفل التطبيق", sub: "الرجوع إلى شاشة كلمة السر", icon: "lock", tint: Brand.red) {
                dialogs.show(ConfirmDialog(title: "قفل التطبيق؟", message: "ستحتاج كلمة السر لفتحه مرة أخرى.", confirm: "قفل", destructive: true) {
                    Task { await model.repo.signOut(); model.pull() }
                })
            }
        }
    }
}

/// Admin section («الإدارة» tab).
struct MoreScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        ScreenList(title: "الإدارة") {
            RoleStrip(user: user)
            SectionHeader(title: "الحسابات وكلمات السر")
            MenuRow(title: "كلمات السر", sub: "العامة، الإدارة، المعلمين", icon: "key.fill", tint: Brand.gold) { router.go(.passwords) }
            MenuRow(title: "المعلمون", sub: "\(snap.teachers().count) معلم • أسماء فقط للتسجيل والتقارير", icon: "person.crop.rectangle") { router.go(.teacherNames) }
            SectionHeader(title: "المركز")
            MenuRow(title: "الحلقات", sub: "\(snap.circles.count) حلقة", icon: "person.3") { router.go(.circles) }
            MenuRow(title: "الطلاب", sub: "\(snap.students.count) طالب", icon: "graduationcap") { router.go(.students) }
            MenuRow(title: "الحضور", sub: "تحضير أي حلقة", icon: "checklist") { router.go(.attendance(nil)) }
            MenuRow(title: "تقرير اليوم للحلقات", sub: "كم حفظوا ومن غاب", icon: "doc.text") { router.go(.circleReport("")) }
            MenuRow(title: "الإعلانات", sub: "\(snap.announcements.count) إعلان", icon: "megaphone") { router.go(.announcements) }
            MenuRow(title: "المكافآت", sub: "النقاط ولوحة الشرف", icon: "trophy") { router.go(.rewards) }
            MenuRow(title: "بيانات المركز", sub: snap.center.name, icon: "building.columns") { router.go(.centerSettings) }
            MenuRow(title: "عن التطبيق", sub: "الإصدار وحالة المزامنة", icon: "info.circle") { router.go(.about) }
        }
    }
}

/// Teachers section «المزيد».
struct TeacherMoreScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        ScreenList(title: "المزيد") {
            RoleStrip(user: user)
            MenuRow(title: "تقرير اليوم", sub: "اختر الحلقة: كم حفظوا ومن غاب، ونشره أو مشاركته", icon: "doc.text", tint: Brand.maroon) { router.go(.circleReport("")) }
            MenuRow(title: "طالب جديد", sub: "إضافة طالب لأي حلقة", icon: "person.badge.plus") { router.go(.studentEdit("new", nil)) }
            MenuRow(title: "الطلاب", sub: "كل الطلاب • تعديل البيانات والصور", icon: "graduationcap") { router.go(.students) }
            MenuRow(title: "المكافآت", sub: "منح النقاط ولوحة الشرف", icon: "trophy") { router.go(.rewards) }
            MenuRow(title: "التقارير", sub: "إحصائيات الحفظ والحضور", icon: "chart.bar.xaxis") { router.go(.reports) }
            MenuRow(title: "الإعلانات", sub: "إعلانات المركز", icon: "megaphone") { router.go(.announcements) }
            MenuRow(title: "عن التطبيق", sub: "الإصدار وحالة المزامنة", icon: "info.circle") { router.go(.about) }
        }
    }
}

/// Admin: the simple list of teacher NAMES (no passwords — all teachers share one password).
struct TeacherNamesScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var dialogs: DialogHost
    var body: some View {
        let snap = model.snap
        let list = snap.teachers()
        ScreenList(title: "المعلمون", fab: Fab(label: "معلم جديد") { dialogs.show(TeacherNameDialog(id: nil, initial: "")) }) {
            AppCard(padding: 12) {
                Text("كل المعلمين يدخلون بكلمة سر واحدة (تغيّرها من «كلمات السر»). الأسماء هنا لاختيار «المعلم المسجِّل» وتظهر في التقارير وعلى الحلقات.")
                    .font(T.bodySmall).foregroundColor(Brand.muted).fixedSize(horizontal: false, vertical: true)
            }
            if list.isEmpty { EmptyState(title: "لا توجد أسماء بعد", message: "أضف أسماء المعلمين (اختياري)") }
            ForEach(list) { t in
                let circles = snap.circles.filter { snap.teacherName(of: $0) == t.name }.map { $0.name }
                AppCard(padding: 12) {
                    HStack(spacing: 12) {
                        Avatar(name: t.name, size: 42, color: Brand.maroon)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name).font(T.titleSmall).foregroundColor(Brand.ink)
                            Text(circles.isEmpty ? "بدون حلقة" : circles.joined(separator: "، ")).font(T.bodySmall).foregroundColor(Brand.muted).lineLimit(1)
                        }
                        Spacer()
                        Button { dialogs.show(TeacherNameDialog(id: t.id, initial: t.name)) } label: {
                            Image(systemName: "pencil").foregroundColor(Brand.navy).frame(width: 36, height: 36)
                        }
                        Button {
                            dialogs.show(ConfirmDialog(title: "حذف \(t.name)؟", message: "يُحذف الاسم من القائمة، وتبقى سجلاته السابقة باسمه.", confirm: "حذف", destructive: true) {
                                model.run("حُذف", { try await model.repo.removeTeacherName(t.id) })
                            })
                        } label: { Image(systemName: "trash").foregroundColor(Brand.red).frame(width: 36, height: 36) }
                    }
                }
            }
        }
    }
}

struct TeacherNameDialog: View {
    let id: String?
    let initial: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var dialogs: DialogHost
    @State private var name = ""
    var body: some View {
        DialogCard(title: id == nil ? "معلم جديد" : "تعديل الاسم") {
            Field(label: "اسم المعلم", text: $name)
        } buttons: {
            DialogButton(title: "إلغاء") { dialogs.dismiss() }
            DialogButton(title: "حفظ", filled: true, enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                let n = name
                model.run("تم الحفظ", { try await model.repo.saveTeacherName(id: id, name: n) }) { _ in dialogs.dismiss() }
            }
        }
        .onAppear { if name.isEmpty { name = initial } }
    }
}

/// Admin: change the general, the admin and the teachers' passwords.
struct PasswordsScreen: View {
    let user: Member
    @EnvironmentObject var dialogs: DialogHost
    var body: some View {
        ScreenList(title: "كلمات السر") {
            AppCard(padding: 12) {
                Text("كلمات السر محفوظة مشفّرة على الخادم ولا تُعرض لأحد. عند تغيير أي كلمة يخرج كل من كان داخلاً بها.")
                    .font(T.bodySmall).foregroundColor(Brand.muted).fixedSize(horizontal: false, vertical: true)
            }
            MenuRow(title: "كلمة السر العامة", sub: "تفتح التطبيق للعرض فقط", icon: "eye", tint: Brand.gold) {
                dialogs.show(SetPasswordDialog(target: .viewer, title: "كلمة السر العامة الجديدة"))
            }
            MenuRow(title: "كلمة سر المعلمين", sub: "واحدة لكل المعلمين، تفتح كل الحلقات", icon: "person.2", tint: Brand.maroon) {
                dialogs.show(SetPasswordDialog(target: .teacher, title: "كلمة سر المعلمين الجديدة"))
            }
            MenuRow(title: "كلمة سر الإدارة", sub: "التحكم الكامل", icon: "lock.shield", tint: Brand.navy) {
                dialogs.show(SetPasswordDialog(target: .admin, title: "كلمة سر الإدارة الجديدة"))
            }
        }
    }
}

struct SetPasswordDialog: View {
    let target: Role
    let title: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var dialogs: DialogHost
    @State private var p1 = ""
    @State private var p2 = ""
    var body: some View {
        DialogCard(title: title) {
            VStack(alignment: .leading, spacing: 8) {
                Field(label: "كلمة السر (6 أحرف أو أرقام على الأقل)", text: $p1, secure: true)
                Field(label: "تأكيدها", text: $p2, secure: true)
                if !p2.isEmpty && Passwords.normalise(p1) != Passwords.normalise(p2) { Text("غير متطابقتين").font(T.bodySmall).foregroundColor(Brand.red) }
            }
        } buttons: {
            DialogButton(title: "إلغاء") { dialogs.dismiss() }
            DialogButton(title: "حفظ", filled: true, enabled: Passwords.normalise(p1).count >= Passwords.minLength && Passwords.normalise(p1) == Passwords.normalise(p2)) {
                let p = p1, t = target
                model.run("تم تغيير كلمة السر", { try await model.repo.setAccessPassword(target: t, password: p) }) { _ in dialogs.dismiss() }
            }
        }
    }
}

/// «تقرير اليوم»: who memorised what today and who was absent, for any circle (circle picker);
/// published in the app (an announcement to everyone) or shared to WhatsApp etc. with the share sheet.
struct CircleReportScreen: View {
    let user: Member
    let circleId: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var idx = -1
    @State private var sharing: ShareItem?

    var body: some View {
        let snap = model.snap
        let circles = Permissions.visibleCircles(user, snap)
        let pick = idx >= 0 ? idx : max(circles.firstIndex { $0.id == circleId } ?? 0, 0)
        let circle = circles.indices.contains(pick) ? circles[pick] : nil
        let text = circle.map { CircleReport.text(snap, $0, Days.today) } ?? ""
        ScreenList(title: "تقرير اليوم") {
            if circles.isEmpty {
                EmptyState(title: "لا توجد حلقات", message: "تنشئها الإدارة من الإعدادات ← الإدارة")
            } else {
                Text("الحلقة").font(T.labelLarge).foregroundColor(Brand.muted)
                ChoiceChips(options: circles.map { $0.name }, selected: pick) { idx = $0 }
                AppCard {
                    Text(text).font(T.bodyMedium).foregroundColor(Brand.ink).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryButton(title: "نشر في التطبيق", icon: "paperplane.fill", enabled: Permissions.canPostAnnouncement(user)) {
                    guard let c = circle else { return }
                    let a = Announcement(id: "", title: "تقرير \(c.name) — \(Days.iso(Days.today))", body: CircleReport.body(snap, c, Days.today),
                                         audience: .all, createdBy: user.id)
                    model.run("نُشر التقرير", { try await model.repo.postAnnouncement(a) })
                }
                OutlineButton(title: "مشاركة (واتساب وغيره)", icon: "square.and.arrow.up") { sharing = ShareItem(text: text) }
            }
        }
        .sheet(item: $sharing) { s in ShareSheet(items: [s.text]) }
    }
}

enum CircleReport {
    static func body(_ snap: CenterSnapshot, _ c: StudyCircle, _ day: Date) -> String {
        let students = snap.studentsIn(c.id).sorted { $0.fullName < $1.fullName }
        let ids = Set(students.map { $0.id })
        let recs = snap.recitations.filter { ids.contains($0.studentId) && Days.dayOf($0.recordedAt) == day }
        let iso = Days.iso(day)
        let att = snap.attendance.filter { ids.contains($0.studentId) && $0.day == iso }
        var lines: [String] = []
        let hifz = recs.filter { $0.kind == .hifz }
        lines.append("حفظ اليوم: \(Set(hifz.map { $0.studentId }).count) طالب • \(hifz.reduce(0) { $0 + Stats.ayatOf($1) }) آية")
        for s in students {
            let mine = recs.filter { $0.studentId == s.id }
            if mine.isEmpty { continue }
            let parts = mine.map { "\($0.kind.short) \(Stats.describeRange($0)) (\($0.grade.label))" }
            lines.append("• \(s.fullName): " + parts.joined(separator: "، "))
        }
        let absent = att.filter { $0.status == .absent }.compactMap { snap.student($0.studentId)?.fullName }
        let late = att.filter { $0.status == .late }.compactMap { snap.student($0.studentId)?.fullName }
        let present = att.filter { $0.status.isPresent }.count
        if att.isEmpty { lines.append("الحضور: لم يُسجَّل بعد") }
        else {
            lines.append("الحضور: \(present) من \(students.count)")
            lines.append("الغائبون: " + (absent.isEmpty ? "لا أحد" : absent.joined(separator: "، ")))
            if !late.isEmpty { lines.append("المتأخرون: " + late.joined(separator: "، ")) }
        }
        return lines.joined(separator: "\n")
    }

    static func text(_ snap: CenterSnapshot, _ c: StudyCircle, _ day: Date) -> String {
        let center = snap.center.name.isEmpty ? "مركز الصديق لتعليم القرآن الكريم" : snap.center.name
        var head = "📖 \(center)\nتقرير \(c.name) — \(Fmt.dayTitle(day))"
        if let t = snap.teacherName(of: c) { head += "\nالمعلم: \(t)" }
        return head + "\n\n" + body(snap, c, day)
    }
}

struct ShareItem: Identifiable { let id = UUID(); let text: String }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct CenterSettingsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var loaded = false
    @State private var name = ""
    @State private var city = ""
    var body: some View {
        ScreenList(title: "بيانات المركز") {
            AppCard {
                VStack(spacing: 10) {
                    Image("Logo").resizable().scaledToFit().frame(width: 110, height: 110).frame(maxWidth: .infinity)
                    Field(label: "اسم المركز", text: $name)
                    Field(label: "الحي / المدينة", text: $city)
                }
            }
            PrimaryButton(title: "حفظ", enabled: Permissions.canManageCenter(user)) {
                let info = CenterInfo(name: name.trimmingCharacters(in: .whitespaces), city: city.trimmingCharacters(in: .whitespaces))
                model.run("تم الحفظ", { try await model.repo.updateCenter(info) }) { _ in router.back() }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = model.snap.center.name; city = model.snap.center.city
        }
    }
}

struct AboutScreen: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let short: String = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build: String = info["CFBundleVersion"] as? String ?? "1"
        let version = "\(short) (\(build))"
        ScreenList(title: "عن التطبيق") {
            AppCard {
                VStack(spacing: 4) {
                    Image("Logo").resizable().scaledToFit().frame(width: 120, height: 120)
                    Text("مركز الصديق لتعليم القرآن الكريم").font(T.titleMedium).foregroundColor(Brand.ink).multilineTextAlignment(.center)
                    Text("الإصدار \(version) • iPhone").font(T.bodySmall).foregroundColor(Brand.muted)
                }
                .frame(maxWidth: .infinity)
                Spacer().frame(height: 12)
                KeyValueRow(key: "مصدر البيانات", value: model.isDemo ? "تجريبي (على الجهاز)" : "قاعدة البيانات المركزية")
                KeyValueRow(key: "المزامنة", value: model.isDemo ? "غير مفعّلة بعد" : syncLabel)
                KeyValueRow(key: "الخادم مُعدّ", value: model.cloudConfigured ? "نعم" : "لا")
            }
            if model.isDemo { DemoBanner() }
        }
    }

    private var syncLabel: String {
        switch model.sync {
        case .synced: return "مفعّلة • متزامن"
        case .pending(let n): return "بانتظار رفع \(n)"
        case .error(let m): return "خطأ: \(m)"
        case .localOnly: return "على الجهاز"
        }
    }
}
