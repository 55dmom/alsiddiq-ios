import SwiftUI

/// The navy frame shared by the opening password screen, the Settings password screens and first-run setup:
/// the ORIGINAL logo (never redrawn) and the centre name, then a white card.
struct GateFrame<Content: View>: View {
    var title: String
    var onBack: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @EnvironmentObject var model: AppModel
    @State private var glow = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    if let onBack = onBack {
                        Button(action: onBack) {
                            Image(systemName: "arrow.backward").font(.system(size: 19, weight: .semibold))
                                .foregroundColor(.white).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("رجوع")
                    }
                    Spacer()
                    ToolsButton()
                }
                .frame(height: 44)
                ZStack {
                    SwiftUI.Circle().fill(Brand.gold.opacity(glow ? 0.38 : 0.18)).frame(width: 170, height: 170).blur(radius: 26)
                    RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.white).frame(width: 132, height: 132)
                        .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 6)
                    Image("Logo").resizable().scaledToFit().frame(width: 118, height: 118)
                }
                .frame(height: 170)
                Spacer().frame(height: 6)
                Text(model.centerName.isEmpty ? "مركز الصديق لتعليم القرآن الكريم" : model.centerName)
                    .font(T.headlineSmall).foregroundColor(.white).multilineTextAlignment(.center)
                Rectangle().fill(Brand.gold).frame(width: 54, height: 3).cornerRadius(2).padding(.top, 10)
                Spacer().frame(height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(T.titleLarge).foregroundColor(Brand.ink)
                    Spacer().frame(height: 14)
                    content()
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
                .shadow(color: Brand.navy.opacity(0.18), radius: 16, x: 0, y: 8)
                if model.isDemo {
                    Spacer().frame(height: 16)
                    DemoBanner()
                    Text("كلمات السر التجريبية: العامة \(DemoSeed.viewerPassword) • الإدارة \(DemoSeed.adminPassword) • المعلمين \(DemoSeed.teacherPassword)")
                        .font(T.labelSmall).foregroundColor(Brand.muted).multilineTextAlignment(.center).padding(.top, 8)
                }
                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 22)
        }
        .background(
            LinearGradient(stops: [.init(color: Brand.navy, location: 0), .init(color: Brand.navyDark, location: 0.36), .init(color: Brand.bg, location: 0.66)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear { withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { glow = true } }
    }
}

/// One password field, nothing else. The password itself decides who you are.
struct PasswordInput: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    @State private var reveal = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock").foregroundColor(Brand.muted).frame(width: 22)
            Group {
                if reveal { TextField(placeholder, text: $text) }
                else { SecureField(placeholder, text: $text) }
            }
            .font(T.bodyLarge)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .submitLabel(.go)
            .onSubmit(onSubmit)
            .accessibilityIdentifier("passwordField")
            Button { reveal.toggle() } label: {
                Image(systemName: reveal ? "eye.slash" : "eye").foregroundColor(Brand.muted)
            }
            .accessibilityLabel(reveal ? "إخفاء" : "إظهار")
        }
        .padding(.horizontal, 14).frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.gold.opacity(0.7), lineWidth: 1.4))
    }
}

/// The opening screen: ONE password field. Shows first-run setup while the centre needs setup.
struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var pass = ""
    @State private var busy = false
    @State private var error: String?
    @State private var needsSetup: Bool?

    private func submit() {
        if Passwords.normalise(pass).isEmpty { error = "اكتب كلمة السر"; return }
        busy = true; error = nil
        Task {
            do { _ = try await model.repo.signIn(password: pass, kind: nil); model.pull(); pass = "" }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? "تعذّر الدخول"; pass = "" }
            busy = false
        }
    }

    var body: some View {
        Group {
            if needsSetup == true {
                SetupView { needsSetup = false }
            } else {
                GateFrame(title: "أدخل كلمة السر") {
                    PasswordInput(placeholder: "كلمة السر", text: $pass, onSubmit: submit)
                    if let error = error {
                        Text(error).font(T.bodySmall).foregroundColor(Brand.red).padding(.top, 8).accessibilityIdentifier("loginError")
                    }
                    Spacer().frame(height: 16)
                    PrimaryButton(title: "دخول", busy: busy) { submit() }.accessibilityIdentifier("loginButton")
                }
            }
        }
        .task {
            if !model.isDemo { needsSetup = await model.repo.needsSetup(); model.pull() }
        }
    }
}

/// Settings → «الإدارة» / «المعلمين»: a password screen that accepts only its own kind.
struct RoleLoginView: View {
    let kind: Role
    let onBack: () -> Void
    @EnvironmentObject var model: AppModel
    @State private var pass = ""
    @State private var busy = false
    @State private var error: String?

    private func submit() {
        if Passwords.normalise(pass).isEmpty { error = "اكتب كلمة السر"; return }
        busy = true; error = nil
        Task {
            do { _ = try await model.repo.signIn(password: pass, kind: kind); model.pull() }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? "تعذّر الدخول"; pass = "" }
            busy = false
        }
    }

    var body: some View {
        GateFrame(title: kind == .admin ? "دخول الإدارة" : "دخول المعلمين", onBack: onBack) {
            Text(kind == .admin ? "اكتب كلمة سر الإدارة للتحكم في التطبيق" : "اكتب كلمة سر المعلمين لإدارة الحلقات والطلاب")
                .font(T.bodySmall).foregroundColor(Brand.muted).fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 12)
            PasswordInput(placeholder: kind == .admin ? "كلمة سر الإدارة" : "كلمة سر المعلمين", text: $pass, onSubmit: submit)
            if let error = error {
                Text(error).font(T.bodySmall).foregroundColor(Brand.red).padding(.top, 8).accessibilityIdentifier("loginError")
            }
            Spacer().frame(height: 16)
            PrimaryButton(title: "دخول", color: kind == .admin ? Brand.navy : Brand.maroon, busy: busy) { submit() }
                .accessibilityIdentifier("loginButton")
        }
    }
}
