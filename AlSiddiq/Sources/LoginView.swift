import SwiftUI

/// The navy frame shared by the opening password screen, the Settings password screens and first-run setup:
/// the ORIGINAL logo (never redrawn) and the centre name, then a white card.
struct GateFrame<Content: View>: View {
    var title: String
    var onBack: (() -> Void)? = nil
    /// The opening screen only: the prayer times and the tools under the password card (no password needed).
    var showTools = false
    @ViewBuilder var content: () -> Content
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tools: ToolsHost
    @State private var glow = false
    @State private var shown = false

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    if let onBack = onBack {
                        Button(action: onBack) {
                            Image(systemName: "arrow.backward").font(.system(size: 19, weight: .semibold))
                                .foregroundColor(Lux.goldLight).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("رجوع")
                    }
                    Spacer()
                    AboutButtonSmall()
                    ToolsButton()
                }
                .frame(height: 44)
                // the ORIGINAL logo inside a gold ring with a soft glow
                ZStack {
                    SwiftUI.Circle().fill(Lux.gold.opacity(glow ? 0.34 : 0.14)).frame(width: 186, height: 186).blur(radius: 28)
                    SwiftUI.Circle().stroke(Lux.goldGradient, lineWidth: 1).frame(width: 162, height: 162).opacity(0.55)
                    SwiftUI.Circle().fill(Color.white).frame(width: 140, height: 140)
                        .overlay(SwiftUI.Circle().stroke(Lux.goldGradient, lineWidth: 4))
                        .shadow(color: Lux.gold.opacity(0.45), radius: 16, x: 0, y: 0)
                    Image("Logo").resizable().scaledToFit().frame(width: 112, height: 112)
                }
                .frame(height: 190)
                .scaleEffect(shown ? 1 : 0.86)
                GoldDivider().padding(.top, 8)
                Text(model.centerName.isEmpty ? "مركز الصديق لتعليم القرآن الكريم" : model.centerName)
                    .font(Lux.title(30)).foregroundStyle(LinearGradient(colors: [.white, Lux.goldLight], startPoint: .top, endPoint: .bottom))
                    .multilineTextAlignment(.center).lineSpacing(4).padding(.top, 8)
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                GoldDivider(width: 46).padding(.top, 10)
                OccasionCard().padding(.top, 16)
                SyncLine().padding(.top, 10)
                Spacer().frame(height: 22)
                // frosted-glass card with a gold hairline
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(T.titleLarge).foregroundColor(.white)
                    Spacer().frame(height: 14)
                    content()
                }
                .padding(20)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Lux.greenDeep.opacity(0.45))
                    }
                    .environment(\.colorScheme, .dark)
                )
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Lux.goldGradient, lineWidth: 0.8).opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                .offset(y: shown ? 0 : 26)
                if model.isDemo {
                    Spacer().frame(height: 16)
                    DemoBanner()
                    Text("كلمات السر التجريبية: العامة \(DemoSeed.viewerPassword) • الإدارة \(DemoSeed.adminPassword) • المعلمين \(DemoSeed.teacherPassword)")
                        .font(T.labelSmall).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.top, 8)
                }
                if showTools {
                    Spacer().frame(height: 22)
                    // the tools block keeps its own look on its own light panel
                    ToolsHome(open: { tools.show($0) }, showExtras: false)
                        .padding(.top, 14).padding(.bottom, 18)
                        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Brand.bg))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Lux.gold.opacity(0.5), lineWidth: 0.8))
                        .padding(.horizontal, -10)
                }
                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 22)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { if showTools { ciScrollToTools(proxy) } }
        }
        .background(LuxBackground())
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { shown = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { glow = true }
        }
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
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
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
                GateFrame(title: "أدخل كلمة السر", showTools: true) {
                    PasswordInput(placeholder: "كلمة السر", text: $pass, onSubmit: submit)
                    if let error = error {
                        Text(error).font(T.bodySmall).foregroundColor(Color(hex: 0xFF9C8F)).padding(.top, 8).accessibilityIdentifier("loginError")
                    }
                    Spacer().frame(height: 16)
                    GoldButton(title: "دخول", busy: busy) { submit() }.accessibilityIdentifier("loginButton")
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
            Text(kind == .admin ? "اكتب كلمة سر الإدارة للتحكم في التطبيق" : "اكتب كلمة سرك التي أعطتك إياها الإدارة لإدارة حلقتك")
                .font(T.bodySmall).foregroundColor(.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 12)
            PasswordInput(placeholder: kind == .admin ? "كلمة سر الإدارة" : "كلمة سر المعلم", text: $pass, onSubmit: submit)
            if let error = error {
                Text(error).font(T.bodySmall).foregroundColor(Color(hex: 0xFF9C8F)).padding(.top, 8).accessibilityIdentifier("loginError")
            }
            Spacer().frame(height: 16)
            GoldButton(title: "دخول", busy: busy) { submit() }
                .accessibilityIdentifier("loginButton")
        }
    }
}
