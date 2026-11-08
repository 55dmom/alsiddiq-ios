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
                    if let p = a.imagePath { AnnouncementPhoto(path: p).padding(.top, 10) }   // v3.8
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
    // v3.8: an optional photo (admin only)
    @State private var photo: Data? = nil
    @State private var picker: PhotoSource? = nil
    @State private var choosing = false
    var body: some View {
        ScreenList(title: "إعلان جديد") {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    Field(label: "العنوان", text: $title)
                    Field(label: "نص الإعلان", text: $text, multiline: true, minLines: 5)
                    Text("يصل إلى").font(T.labelMedium).foregroundColor(Brand.muted).padding(.top, 2)
                    ChoiceChips(options: AnnounceNewScreen.audiences.map { $0.label }, selected: aud) { aud = $0 }
                    if user.role == .admin {
                        Text("صورة (اختياري)").font(T.labelMedium).foregroundColor(Brand.muted).padding(.top, 2)
                        if let d = photo, let img = UIImage(data: d) {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        Button { choosing = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "camera").font(.system(size: 14, weight: .semibold))
                                Text(photo == nil ? "إضافة صورة" : "تغيير الصورة").font(T.labelLarge)
                            }
                            .foregroundColor(Brand.navy).padding(.horizontal, 12).frame(height: 36)
                            .background(Capsule().fill(Brand.navy.opacity(0.08)))
                        }
                        .accessibilityIdentifier("announcementPhoto")
                    }
                }
            }
            PrimaryButton(title: "نشر الإعلان", icon: "paperplane.fill",
                          enabled: Permissions.canPostAnnouncement(user) && !title.trimmingCharacters(in: .whitespaces).isEmpty) {
                let a = Announcement(id: UUID().uuidString.lowercased(), title: title.trimmingCharacters(in: .whitespaces), body: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                     audience: AnnounceNewScreen.audiences[aud], createdBy: user.id)
                let img = user.role == .admin ? photo : nil
                model.run("نُشر الإعلان", {
                    // the photo goes up first (needs internet), then the announcement carries its path
                    var x = a
                    if let img = img { x.imagePath = try await model.repo.uploadAnnouncementImage(announcementId: x.id, jpeg: img) }
                    return try await model.repo.postAnnouncement(x)
                }) { _ in router.back() }
            }
        }
        .confirmationDialog("صورة الإعلان", isPresented: $choosing, titleVisibility: .visible) {
            Button("المعرض") { picker = .library }
            Button("الكاميرا") { picker = .camera }
            if photo != nil { Button("إزالة الصورة", role: .destructive) { photo = nil } }
            Button("إلغاء", role: .cancel) {}
        }
        .sheet(item: $picker) { src in
            PhotoPickerSheet(source: src) { img in
                picker = nil
                if let img = img {
                    photo = [1280, 1024, 800, 640].lazy.compactMap({ PhotoTools.jpeg(img, maxSide: CGFloat($0)) }).first(where: { $0.count <= 280_000 }) ?? PhotoTools.jpeg(img, maxSide: 512)
                }
            }
            .ignoresSafeArea()
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
