import SwiftUI

/// First run on a brand-new central database: the owner creates the centre and his own admin account.
struct SetupView: View {
    let onDone: () -> Void
    @EnvironmentObject var model: AppModel
    @State private var center = "مركز الصديق لتعليم القرآن الكريم"
    @State private var name = ""
    @State private var phone = ""
    @State private var pass = ""
    @State private var pass2 = ""
    @State private var busy = false
    @State private var error: String?

    private func validate() -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "اكتب اسمك" }
        if Phone.normalise(phone).count < 8 { return "رقم الجوال غير صحيح" }
        if pass.count < 6 { return "كلمة المرور 6 أحرف على الأقل" }
        if pass != pass2 { return "كلمتا المرور غير متطابقتين" }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 32)
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.white)
                    Image("Logo").resizable().scaledToFit().frame(width: 96, height: 96)
                }
                .frame(width: 108, height: 108)
                Spacer().frame(height: 12)
                Text("إعداد المركز لأول مرة").font(T.headlineSmall).foregroundColor(.white)
                Text("أنشئ حساب الإدارة الخاص بك. بعدها تضيف المعلمين والطلاب وأولياء الأمور من داخل التطبيق.")
                    .font(T.bodySmall).foregroundColor(.white.opacity(0.85)).multilineTextAlignment(.center)
                Spacer().frame(height: 20)
                VStack(alignment: .leading, spacing: 10) {
                    Field(label: "اسم المركز", text: $center)
                    Field(label: "اسمك", text: $name)
                    Field(label: "رقم جوالك (للدخول)", text: $phone, keyboard: .phonePad)
                    Field(label: "كلمة المرور (6 أحرف على الأقل)", text: $pass, secure: true)
                    Field(label: "تأكيد كلمة المرور", text: $pass2, secure: true)
                    if let e = error { Text(e).font(T.bodySmall).foregroundColor(Brand.red) }
                    PrimaryButton(title: "إنشاء المركز والدخول", busy: busy) {
                        error = validate()
                        guard error == nil else { return }
                        busy = true
                        Task {
                            do {
                                _ = try await model.repo.bootstrap(centerName: center.trimmingCharacters(in: .whitespaces),
                                                                   fullName: name.trimmingCharacters(in: .whitespaces), phone: phone, password: pass)
                                model.pull()
                                onDone()
                            } catch {
                                self.error = (error as? LocalizedError)?.errorDescription ?? "تعذّر الإعداد"
                            }
                            busy = false
                        }
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
                .shadow(color: Brand.navy.opacity(0.18), radius: 16, x: 0, y: 8)
                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 22)
        }
        .background(
            LinearGradient(stops: [.init(color: Brand.navy, location: 0), .init(color: Brand.navyDark, location: 0.32), .init(color: Brand.bg, location: 0.62)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        )
    }
}
