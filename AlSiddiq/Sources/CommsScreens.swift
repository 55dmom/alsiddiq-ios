import SwiftUI

struct AnnouncementsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var dialogs: DialogHost
    var body: some View {
        let snap = model.snap
        let list = snap.announcements.sorted { $0.createdAt > $1.createdAt }
        ScreenList(title: "الإعلانات", fab: Permissions.canPostAnnouncement(user) ? Fab(label: "إعلان جديد") { router.go(.announceNew) } : nil) {
            if list.isEmpty { EmptyState(title: "لا توجد إعلانات", message: "ستظهر هنا إعلانات المركز") }
            ForEach(list) { a in
                AppCard {
                    HStack(spacing: 10) {
                        IconBadge(icon: "megaphone", tint: Brand.maroon, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.title).font(T.titleSmall).foregroundColor(Brand.ink)
                            Text("\((a.byName.isEmpty ? (snap.member(a.createdBy)?.role == .teacher ? "المعلمون" : "الإدارة") : a.byName)) • \(Fmt.relative(a.createdAt))").font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                        Spacer()
                        Pill(text: a.audience.label, color: Brand.navy)
                    }
                    Text(a.body).font(T.bodyMedium).foregroundColor(Brand.ink).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                    if user.role == .admin || (user.role == .teacher && a.createdBy == user.id) {
                        TextAction(title: "حذف", color: Brand.red) {
                            dialogs.show(ConfirmDialog(title: "حذف الإعلان؟", message: a.title, confirm: "حذف", destructive: true) {
                                model.run("حُذف الإعلان", { try await model.repo.deleteAnnouncement(a.id) })
                            })
                        }
                    }
                }
            }
        }
    }
}

struct AnnounceNewScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var title = ""
    @State private var text = ""
    @State private var aud = 0
    var body: some View {
        ScreenList(title: "إعلان جديد") {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    Field(label: "العنوان", text: $title)
                    Field(label: "نص الإعلان", text: $text, multiline: true, minLines: 5)
                    Text("يصل إلى").font(T.labelMedium).foregroundColor(Brand.muted).padding(.top, 2)
                    ChoiceChips(options: AnnounceNewScreen.audiences.map { $0.label }, selected: aud) { aud = $0 }
                }
            }
            PrimaryButton(title: "نشر الإعلان", icon: "paperplane.fill",
                          enabled: Permissions.canPostAnnouncement(user) && !title.trimmingCharacters(in: .whitespaces).isEmpty) {
                let a = Announcement(id: "", title: title.trimmingCharacters(in: .whitespaces), body: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                     audience: AnnounceNewScreen.audiences[aud], createdBy: user.id)
                model.run("نُشر الإعلان", { try await model.repo.postAnnouncement(a) }) { _ in router.back() }
            }
        }
    }
}

extension AnnounceNewScreen {
    /// v3: no parent/student accounts; "الجميع" reaches the general view too.
    static let audiences: [Audience] = [.all, .teachers]
}

struct NotificationsScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        let list = snap.notifications.sorted { $0.createdAt > $1.createdAt }
        ScreenList(title: "الإشعارات", actions: {
            if list.contains(where: { !$0.read }) {
                TextAction(title: "قراءة الكل", color: Brand.navy) { model.run("تم تعليم الكل كمقروء", { try await model.repo.markAllNotificationsRead() }) }
            }
        }) {
            if list.isEmpty { EmptyState(title: "لا توجد إشعارات", message: "ستصلك هنا تحديثات الحفظ والحضور والإعلانات") }
            ForEach(list) { n in
                AppCard(padding: 12, onTap: { open(n, snap) }) {
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            SwiftUI.Circle().fill(n.read ? Brand.line : Brand.navySoft)
                            Image(systemName: icon(n.kind)).font(.system(size: 17)).foregroundColor(n.read ? Brand.muted : Brand.navy)
                        }.frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(n.title).font(AppFont.f(14, n.read ? .medium : .bold)).foregroundColor(Brand.ink)
                            Text(n.body).font(T.bodySmall).foregroundColor(Brand.muted).fixedSize(horizontal: false, vertical: true)
                            Text(Fmt.relative(n.createdAt)).font(T.labelSmall).foregroundColor(Brand.muted)
                        }
                        Spacer()
                        if !n.read { SwiftUI.Circle().fill(Brand.maroon).frame(width: 9, height: 9).padding(.top, 6) }
                    }
                }
            }
        }
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "record": return "book"
        case "absence": return "calendar.badge.exclamationmark"
        case "reward": return "trophy"
        case "announcement": return "megaphone"
        default: return "bell"
        }
    }

    private func open(_ n: AppNotification, _ snap: CenterSnapshot) {
        if !n.read { model.run(nil, { try await model.repo.markNotificationRead(n.id) }) }
        switch n.kind {
        case "announcement": router.go(.announcements)
        case "absence": if let r = n.refId, snap.student(r) != nil { router.go(.student(r)) }
        default: break
        }
    }
}
