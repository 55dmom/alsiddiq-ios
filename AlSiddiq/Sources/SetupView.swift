import SwiftUI

/// First run (the centre «needs setup»): centre name (pre-filled) + admin password + general password
/// (+ the teachers' password when the server takes it at setup). 6+ characters each, all different.
struct SetupView: View {
    let onDone: () -> Void
    @EnvironmentObject var model: AppModel
    @State private var center = ""
    @State private var admin = ""
    @State private var admin2 = ""
    @State private var viewer = ""
    @State private var viewer2 = ""
    @State private var teacher = ""
    @State private var busy = false
    @State private var error: String?

    private func validate() -> String? {
        let a = Passwords.normalise(admin), v = Passwords.normalise(viewer), t = Passwords.normalise(teacher)
        if center.trimmingCharacters(in: .whitespaces).isEmpty { return "اكتب اسم المركز" }
        if let bad = Passwords.check(a) { return bad }
        if a != Passwords.normalise(admin2) { return "كلمتا سر الإدارة غير متطابقتين" }
        if let bad = Passwords.check(v) { return bad }
        if v != Passwords.normalise(viewer2) { return "كلمتا السر العامة غير متطابقتين" }
        if a == v { return "كلمة سر الإدارة يجب أن تختلف عن كلمة السر العامة" }
        if SetupView.asksTeacherPassword {
            if let bad = Passwords.check(t) { return bad }
            if t == a || t == v { return "كلمة سر المعلمين يجب أن تختلف عن غيرها" }
        }
        return nil
    }

    var body: some View {
        GateFrame(title: "إعداد المركز لأول مرة") {
            VStack(alignment: .leading, spacing: 10) {
                Text("اختر كلمات السر. الكلمة العامة تفتح التطبيق للعرض فقط، وكلمة الإدارة للتحكم الكامل.")
                    .font(T.bodySmall).foregroundColor(Brand.muted).fixedSize(horizontal: false, vertical: true)
                Field(label: "اسم المركز", text: $center)
                Field(label: "كلمة سر الإدارة (6 أحرف أو أرقام على الأقل)", text: $admin, secure: true)
                Field(label: "تأكيد كلمة سر الإدارة", text: $admin2, secure: true)
                Field(label: "كلمة السر العامة (للعرض فقط)", text: $viewer, secure: true)
                Field(label: "تأكيد كلمة السر العامة", text: $viewer2, secure: true)
                if SetupView.asksTeacherPassword {
                    Field(label: "كلمة سر المعلمين (تفتح كل الحلقات)", text: $teacher, secure: true)
                }
                if let e = error { Text(e).font(T.bodySmall).foregroundColor(Brand.red) }
                PrimaryButton(title: "حفظ والدخول", busy: busy) {
                    error = validate()
                    guard error == nil else { return }
                    busy = true
                    Task {
                        do {
                            _ = try await model.repo.setup(centerName: center.trimmingCharacters(in: .whitespaces), adminPassword: admin,
                                                           viewerPassword: viewer, teacherPassword: SetupView.asksTeacherPassword ? teacher : nil)
                            model.pull()
                            onDone()
                        } catch {
                            self.error = (error as? LocalizedError)?.errorDescription ?? "تعذّر الإعداد"
                        }
                        busy = false
                    }
                }
            }
        }
        .onAppear {
            if center.isEmpty { center = model.centerName.isEmpty ? "مركز الصديق لتعليم القرآن الكريم" : model.centerName }
        }
    }
}

extension SetupView {
    /// v3.1: whether first-run setup also asks for the shared teachers' password (as the server's setup takes it).
    static let asksTeacherPassword = true
}
