import SwiftUI

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var phone = ""
    @State private var pass = ""
    @State private var busy = false
    @State private var error: String?

    let demos: [(String, String)] = [("الإدارة", DemoSeed.adminPhone), ("معلم", DemoSeed.teacherPhone),
                                             ("طالب", DemoSeed.studentPhone), ("ولي أمر", DemoSeed.parentPhone)]

    private func submit() {
        if phone.trimmingCharacters(in: .whitespaces).isEmpty || pass.isEmpty { error = "أدخل رقم الجوال وكلمة المرور"; return }
        busy = true; error = nil
        Task {
            do { _ = try await model.repo.signIn(login: phone, password: pass); model.pull() }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? "تعذّر تسجيل الدخول" }
            busy = false
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 48)
                ZStack {
                    RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.white)
                    Image("Logo").resizable().scaledToFit().frame(width: 118, height: 118)
                }
                .frame(width: 132, height: 132)
                .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 6)
                Spacer().frame(height: 16)
                Text("مركز الصديق").font(T.headlineMedium).foregroundColor(.white)
                Text("لتعليم القرآن الكريم").font(T.bodyLarge).foregroundColor(.white.opacity(0.8))
                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 0) {
                    Text("تسجيل الدخول").font(T.titleLarge).foregroundColor(Brand.ink)
                    Text("أدخل رقم جوالك وكلمة المرور التي زوّدتك بها إدارة المركز").font(T.bodySmall).foregroundColor(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer().frame(height: 16)
                    LoginField(icon: "phone", placeholder: "رقم الجوال", text: $phone, keyboard: .phonePad)
                    Spacer().frame(height: 10)
                    LoginField(icon: "lock", placeholder: "كلمة المرور", text: $pass, secure: true)
                    if let error = error {
                        Text(error).font(T.bodySmall).foregroundColor(Brand.red).padding(.top, 8)
                    }
                    Spacer().frame(height: 18)
                    PrimaryButton(title: "دخول", busy: busy) { submit() }
                    Text("نسيت كلمة المرور؟ تواصل مع إدارة المركز لإعادة تعيينها")
                        .font(T.bodySmall).foregroundColor(Brand.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 10)
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
                .shadow(color: Brand.navy.opacity(0.18), radius: 16, x: 0, y: 8)

                if model.isDemo {
                    Spacer().frame(height: 18)
                    DemoBanner()
                    Spacer().frame(height: 10)
                    Text("جرّب بحساب تجريبي (كلمة المرور \(DemoSeed.demoPassword))").font(T.labelMedium).foregroundColor(Brand.muted)
                    Spacer().frame(height: 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(demos.enumerated()), id: \.offset) { _, item in
                                AssistChip(title: item.0) { phone = item.1; pass = DemoSeed.demoPassword; submit() }
                            }
                        }
                    }
                }
                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 22)
        }
        .background(
            LinearGradient(stops: [.init(color: Brand.navy, location: 0), .init(color: Brand.navyDark, location: 0.32), .init(color: Brand.bg, location: 0.62)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

struct LoginField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure = false
    @State private var reveal = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(Brand.muted).frame(width: 22)
            Group {
                if secure && !reveal { SecureField(placeholder, text: $text) }
                else { TextField(placeholder, text: $text) }
            }
            .font(T.bodyLarge)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            if secure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye").foregroundColor(Brand.muted)
                }
                .accessibilityLabel(reveal ? "إخفاء" : "إظهار")
            }
        }
        .padding(.horizontal, 14).frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.line, lineWidth: 1.2))
    }
}
