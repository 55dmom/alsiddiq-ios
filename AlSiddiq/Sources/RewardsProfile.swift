import SwiftUI

struct AwardBadge {
    let title: String
    let icon: String
    let earned: Bool
}

func badgesFor(_ st: StudentStats) -> [AwardBadge] {
    [
        AwardBadge(title: "أول جزء", icon: "book.closed", earned: st.juzEquivalent >= 1),
        AwardBadge(title: "100 آية", icon: "text.book.closed", earned: st.memorisedAyat >= 100),
        AwardBadge(title: "أسبوع متواصل", icon: "flame", earned: st.streakDays >= 6),
        AwardBadge(title: "حضور 90%", icon: "calendar.badge.clock", earned: st.attendanceRate >= 0.9 && st.presentDays >= 10),
        AwardBadge(title: "متقن", icon: "rosette", earned: st.averageGrade >= 4.5),
        AwardBadge(title: "5 أجزاء", icon: "diamond", earned: st.juzEquivalent >= 5)
    ]
}

struct RewardsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var dialogs: DialogHost

    var body: some View {
        let snap = model.snap
        let visible = Permissions.visibleStudents(user, snap)
        let canGive = user.role == .admin || user.role == .teacher
        let ids = Set(visible.map { $0.id })
        let history = Array(snap.rewards.filter { ids.contains($0.studentId) }.sorted { $0.createdAt > $1.createdAt }.prefix(30))
        let board = RewardsScreen.leaderboard(visible, snap)

        ScreenList(title: "المكافآت", fab: canGive ? Fab(label: "منح مكافأة") { pickStudent(visible, snap) } : nil) {
            if user.role == .student || user.role == .parent {
                ForEach(visible) { s in
                    let st = Stats.forStudent(s, snap)
                    AppCard {
                        HStack(spacing: 12) {
                            ZStack {
                                SwiftUI.Circle().fill(Brand.goldSoft)
                                Image(systemName: "trophy.fill").font(.system(size: 26)).foregroundColor(Brand.gold)
                            }.frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.fullName).font(T.bodySmall).foregroundColor(Brand.muted)
                                Text("\(st.points) نقطة").font(T.headlineSmall).foregroundColor(Brand.ink)
                            }
                            Spacer()
                        }
                        Text("الأوسمة").font(T.titleSmall).foregroundColor(Brand.ink).padding(.top, 12).padding(.bottom, 8)
                        let badges = badgesFor(st)
                        VStack(spacing: 8) {
                            ForEach(0..<2) { row in
                                HStack(spacing: 8) {
                                    ForEach(0..<3) { col in
                                        let b = badges[row * 3 + col]
                                        VStack(spacing: 4) {
                                            Image(systemName: b.icon).font(.system(size: 24)).foregroundColor(b.earned ? Brand.navy : Brand.line)
                                            Text(b.title).font(T.labelSmall).foregroundColor(b.earned ? Brand.navy : Brand.muted).multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.8)
                                        }
                                        .frame(maxWidth: .infinity).padding(10)
                                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(b.earned ? Brand.navySoft : Brand.bg))
                                    }
                                }
                            }
                        }
                    }
                }
                SectionHeader(title: "سجل النقاط")
            } else {
                SectionHeader(title: "لوحة الشرف")
                ForEach(Array(board.enumerated()), id: \.offset) { i, pair in
                    let rank = i + 1
                    AppCard(padding: 12, onTap: { give(pair.0) }) {
                        HStack(spacing: 10) {
                            Text("\(rank)").font(AppFont.f(14, .bold)).foregroundColor(rank <= 3 ? .white : Brand.navy)
                                .frame(width: 30, height: 30)
                                .background(SwiftUI.Circle().fill(rank == 1 ? Brand.gold : rank == 2 ? Brand.silver : rank == 3 ? Brand.bronze : Brand.navySoft))
                            Text(pair.0.fullName).font(T.bodyMedium).foregroundColor(Brand.ink)
                            Spacer()
                            Text("\(pair.1)").font(T.titleMedium).foregroundColor(Brand.maroon)
                            Text("نقطة").font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                    }
                }
                SectionHeader(title: "أحدث المكافآت")
            }
            if history.isEmpty { EmptyState(title: "لا توجد مكافآت بعد", message: "") }
            ForEach(history) { r in
                AppCard(padding: 12) {
                    HStack(spacing: 10) {
                        Pill(text: "+\(r.points)", color: Brand.green, filled: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.reason).font(T.bodyMedium).foregroundColor(Brand.ink)
                            Text("\(snap.student(r.studentId)?.fullName ?? "") • \(Fmt.relative(r.createdAt))").font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func pickStudent(_ visible: [Student], _ snap: CenterSnapshot) {
        dialogs.show(PickerDialog(title: "اختر الطالب", items: visible.filter { Permissions.canRecordFor(user, $0, snap) }, label: { $0.fullName }, searchable: true) { s in
            Task { @MainActor in try? await Task.sleep(nanoseconds: 250_000_000); give(s) }
        })
    }

    private func give(_ s: Student) {
        guard user.role == .admin || user.role == .teacher else { return }
        dialogs.show(RewardDialog(student: s, user: user))
    }
}

extension RewardsScreen {
    static func leaderboard(_ visible: [Student], _ snap: CenterSnapshot) -> [(Student, Int)] {
        var out: [(Student, Int)] = []
        for s in visible {
            var n = 0
            for r in snap.rewards where r.studentId == s.id { n += r.points }
            out.append((s, n))
        }
        return Array(out.sorted { $0.1 > $1.1 }.prefix(10))
    }
}

struct RewardDialog: View {
    let student: Student
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var dialogs: DialogHost
    @State private var pts = 10
    @State private var reason = "إتقان الحفظ"
    let opts = [5, 10, 15, 20, 50]
    let reasons = ["إتقان الحفظ", "الانضباط في الحضور", "حسن الخلق", "ختم سورة", "التفوق في المسابقة"]
    var body: some View {
        DialogCard(title: "مكافأة لـ \(student.fullName)") {
            VStack(alignment: .leading, spacing: 10) {
                Text("النقاط").font(T.labelMedium).foregroundColor(Brand.muted)
                ChoiceChips(options: opts.map { "+\($0)" }, selected: opts.firstIndex(of: pts) ?? -1) { pts = opts[$0] }
                ChoiceChips(options: reasons, selected: reasons.firstIndex(of: reason) ?? -1) { reason = reasons[$0] }
                Field(label: "السبب", text: $reason)
            }
        } buttons: {
            DialogButton(title: "إلغاء") { dialogs.dismiss() }
            DialogButton(title: "منح", filled: true) {
                let r = Reward(id: "", studentId: student.id, points: pts, reason: reason.trimmingCharacters(in: .whitespaces), awardedBy: user.id)
                model.run("مُنحت المكافأة 🎉", { try await model.repo.giveReward(r) }) { _ in dialogs.dismiss() }
            }
        }
    }
}

struct ProfileScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var dialogs: DialogHost
    var body: some View {
        let snap = model.snap
        ScreenList(title: "حسابي") {
            AppCard {
                VStack(spacing: 4) {
                    Avatar(name: user.fullName, size: 76)
                    Text(user.fullName).font(T.titleLarge).foregroundColor(Brand.ink).padding(.top, 6)
                    Pill(text: user.role.label, color: Brand.maroon)
                    Text(user.phone).font(T.bodySmall).foregroundColor(Brand.muted)
                }
                .frame(maxWidth: .infinity)
            }
            MenuRow(title: "الإشعارات", sub: "\(snap.unreadCount) غير مقروء", icon: "bell") { router.go(.notifications) }
            MenuRow(title: "الإعلانات", sub: "إعلانات المركز", icon: "megaphone") { router.go(.announcements) }
            if user.role == .teacher { MenuRow(title: "المكافآت", sub: "منح النقاط ولوحة الشرف", icon: "trophy") { router.go(.rewards) } }
            if user.role == .parent { MenuRow(title: "المكافآت", sub: "نقاط وأوسمة أبنائي", icon: "trophy") { router.go(.rewards) } }
            MenuRow(title: "تغيير كلمة المرور", sub: "حدّث كلمة المرور الخاصة بك", icon: "key") { dialogs.show(ChangePasswordDialog()) }
            MenuRow(title: "عن التطبيق", sub: "الإصدار وحالة المزامنة", icon: "info.circle") { router.go(.about) }
            MenuRow(title: "تسجيل الخروج", sub: "الخروج من هذا الجهاز", icon: "rectangle.portrait.and.arrow.right", tint: Brand.red) {
                dialogs.show(ConfirmDialog(title: "تسجيل الخروج؟", message: "يمكنك الدخول مرة أخرى برقم جوالك وكلمة المرور.", confirm: "خروج", destructive: true) {
                    Task { await model.repo.signOut(); model.pull() }
                })
            }
        }
    }
}

struct ChangePasswordDialog: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var dialogs: DialogHost
    @State private var old = ""
    @State private var new1 = ""
    @State private var new2 = ""
    var body: some View {
        DialogCard(title: "تغيير كلمة المرور") {
            VStack(alignment: .leading, spacing: 8) {
                Field(label: "كلمة المرور الحالية", text: $old, secure: true)
                Field(label: "كلمة المرور الجديدة", text: $new1, secure: true)
                Field(label: "تأكيد كلمة المرور الجديدة", text: $new2, secure: true)
                if !new2.isEmpty && new1 != new2 { Text("غير متطابقتين").font(T.bodySmall).foregroundColor(Brand.red) }
            }
        } buttons: {
            DialogButton(title: "إلغاء") { dialogs.dismiss() }
            DialogButton(title: "حفظ", filled: true, enabled: !new1.isEmpty && new1 == new2) {
                model.run("تم تغيير كلمة المرور", { try await model.repo.changePassword(old: old, new: new1) }) { _ in dialogs.dismiss() }
            }
        }
    }
}
