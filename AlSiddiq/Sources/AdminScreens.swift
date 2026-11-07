import SwiftUI

struct MoreScreen: View {
    let user: Member
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    var body: some View {
        let snap = model.snap
        ScreenList(title: "المزيد") {
            SectionHeader(title: "الحسابات")
            MenuRow(title: "المعلمون", sub: "\(snap.teachers().count) معلم", icon: "person.crop.rectangle") { router.go(.members(.teacher)) }
            MenuRow(title: "أولياء الأمور", sub: "\(snap.parents().count) ولي أمر", icon: "figure.2.and.child.holdinghands") { router.go(.members(.parent)) }
            MenuRow(title: "حسابات الطلاب", sub: "\(snap.members.filter { $0.role == .student }.count) حساب", icon: "person.text.rectangle") { router.go(.members(.student)) }
            MenuRow(title: "المشرفون والإدارة", sub: "\(snap.members.filter { $0.role == .admin }.count) حساب", icon: "lock.shield") { router.go(.members(.admin)) }
            SectionHeader(title: "المتابعة")
            MenuRow(title: "الحضور والغياب", sub: "تسجيل ومراجعة الحضور", icon: "checklist") { router.go(.attendance(nil)) }
            MenuRow(title: "المكافآت والنقاط", sub: "لوحة الشرف ومنح النقاط", icon: "trophy") { router.go(.rewards) }
            MenuRow(title: "الإعلانات", sub: "\(snap.announcements.count) إعلان", icon: "megaphone") { router.go(.announcements) }
            MenuRow(title: "الإشعارات", sub: "\(snap.unreadCount) غير مقروء", icon: "bell") { router.go(.notifications) }
            SectionHeader(title: "الإعدادات")
            MenuRow(title: "بيانات المركز", sub: snap.center.name, icon: "building.columns") { router.go(.settings) }
            MenuRow(title: "حسابي", sub: user.fullName, icon: "person") { router.go(.profile) }
            MenuRow(title: "عن التطبيق", sub: "الإصدار وحالة المزامنة", icon: "info.circle") { router.go(.about) }
        }
    }
}

struct MembersScreen: View {
    let user: Member
    let role: Role
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var q = ""
    var body: some View {
        let snap = model.snap
        let needle = q.trimmingCharacters(in: .whitespaces)
        let list = snap.members.filter { $0.role == role && (needle.isEmpty || $0.fullName.contains(needle) || $0.phone.contains(needle)) }
        let title: String = {
            switch role { case .teacher: return "المعلمون"; case .parent: return "أولياء الأمور"; case .student: return "حسابات الطلاب"; case .admin: return "الإدارة" }
        }()
        ScreenList(title: title, fab: Permissions.canManageMembers(user) ? Fab(label: "إضافة") { router.go(.memberEdit(role, "new")) } : nil) {
            SearchField(placeholder: "بحث بالاسم أو الجوال", text: $q)
            if list.isEmpty { EmptyState(title: "لا توجد حسابات", message: "أضف أول حساب من زر الإضافة") }
            ForEach(list) { m in
                AppCard(padding: 12, onTap: { router.go(.memberEdit(role, m.id)) }) {
                    HStack(spacing: 12) {
                        Avatar(name: m.fullName, color: m.role == .teacher ? Brand.maroon : Brand.navy)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.fullName).font(T.titleSmall).foregroundColor(Brand.ink)
                            Text(m.phone + " • " + extra(m, snap)).font(T.bodySmall).foregroundColor(Brand.muted).lineLimit(1)
                        }
                        Spacer()
                        if !m.active { Pill(text: "موقوف", color: Brand.red) }
                    }
                }
            }
        }
    }

    private func extra(_ m: Member, _ snap: CenterSnapshot) -> String {
        switch m.role {
        case .teacher:
            let s = snap.circles.filter { $0.teacherId == m.id }.map { $0.name }.joined(separator: "، ")
            return s.isEmpty ? "بدون حلقة" : s
        case .parent:
            let s = m.childIds.compactMap { snap.student($0)?.fullName }.joined(separator: "، ")
            return s.isEmpty ? "لم يُربط بأبناء" : s
        case .student:
            return snap.student(m.studentId).flatMap { snap.circle($0.circleId)?.name } ?? ""
        case .admin:
            return m.role.label
        }
    }
}

struct MemberEditScreen: View {
    let user: Member
    let role: Role
    let id: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var dialogs: DialogHost
    @State private var loaded = false
    @State private var name = ""
    @State private var phone = ""
    @State private var pass = ""
    @State private var active = true
    @State private var children: [String] = []
    @State private var studentId: String?

    var body: some View {
        let snap = model.snap
        let existing = snap.member(id)
        let canEdit = Permissions.canManageMembers(user)
        ScreenList(title: (existing == nil ? "إضافة " : "تعديل ") + role.label) {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    Field(label: "الاسم الكامل", text: $name)
                    Field(label: "رقم الجوال (يُستخدم لتسجيل الدخول)", text: $phone, keyboard: .phonePad)
                    if existing == nil { Field(label: "كلمة مرور مؤقتة (6 أحرف على الأقل)", text: $pass) }
                    if let e = existing {
                        Toggle(isOn: $active) { Text("الحساب مفعّل").font(T.bodyMedium).foregroundColor(Brand.ink) }
                            .tint(Brand.navy).disabled(e.id == user.id)
                    }
                }
            }
            if role == .parent {
                SectionHeader(title: "الأبناء المرتبطون", action: "ربط ابن") {
                    dialogs.show(PickerDialog(title: "اختر الابن", items: snap.students.filter { !children.contains($0.id) }, label: { $0.fullName }, searchable: true) { children.append($0.id) })
                }
                if children.isEmpty {
                    Text("لم يُربط أي ابن بعد. ولي الأمر يرى أبناءه المرتبطين فقط.").font(T.bodySmall).foregroundColor(Brand.muted)
                }
                ForEach(children, id: \.self) { cid in
                    let s = snap.student(cid)
                    AppCard(padding: 10) {
                        HStack(spacing: 10) {
                            Avatar(name: s?.fullName ?? "؟", size: 36)
                            Text(s?.fullName ?? "طالب محذوف").font(T.bodyMedium).foregroundColor(Brand.ink)
                            Spacer()
                            Button { children.removeAll { $0 == cid } } label: {
                                Image(systemName: "link.badge.plus").rotationEffect(.degrees(45)).foregroundColor(Brand.red).frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("إلغاء الربط")
                        }
                    }
                }
            }
            if role == .student {
                SectionHeader(title: "سجل الطالب المرتبط")
                SelectorField(label: "الطالب", value: snap.student(studentId)?.fullName ?? "اختر الطالب") {
                    dialogs.show(PickerDialog(title: "اختر الطالب", items: snap.students, label: { $0.fullName }, searchable: true) { studentId = $0.id })
                }
            }
            PrimaryButton(title: existing == nil ? "إنشاء الحساب" : "حفظ", enabled: canEdit) {
                if let e = existing {
                    var m = e
                    m.fullName = name.trimmingCharacters(in: .whitespaces)
                    m.phone = Phone.normalise(phone)
                    m.active = active
                    m.childIds = children
                    m.studentId = studentId
                    model.run("تم حفظ التعديلات", { try await model.repo.updateMember(m) }) { _ in router.back() }
                } else {
                    let nm = NewMember(fullName: name, phone: phone, role: role, password: pass, studentId: studentId, childIds: children)
                    model.run("تمت إضافة الحساب", { try await model.repo.createMember(nm) }) { _ in router.back() }
                }
            }
            .padding(.top, 8)
            if let e = existing {
                OutlineButton(title: "إعادة تعيين كلمة المرور", icon: "lock.rotation", enabled: canEdit) { dialogs.show(ResetPasswordDialog(memberId: e.id)) }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = model.snap.member(id) {
                name = e.fullName; phone = e.phone; active = e.active; children = e.childIds; studentId = e.studentId
            }
        }
    }
}

struct ResetPasswordDialog: View {
    let memberId: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var dialogs: DialogHost
    @State private var np = ""
    var body: some View {
        DialogCard(title: "كلمة مرور جديدة") {
            Field(label: "6 أحرف على الأقل", text: $np)
        } buttons: {
            DialogButton(title: "إلغاء") { dialogs.dismiss() }
            DialogButton(title: "تعيين", filled: true) {
                model.run("تم تعيين كلمة المرور", { try await model.repo.resetMemberPassword(memberId: memberId, newPassword: np) }) { _ in dialogs.dismiss() }
            }
        }
    }
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
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") + ")"
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
