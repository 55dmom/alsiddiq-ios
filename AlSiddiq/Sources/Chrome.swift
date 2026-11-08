import SwiftUI

private struct CanGoBackKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True for screens pushed on top of a tab root.
    var canGoBack: Bool {
        get { self[CanGoBackKey.self] }
        set { self[CanGoBackKey.self] = newValue }
    }
}

struct TopBar<Actions: View>: View {
    let title: String
    let showBack: Bool
    let onBack: () -> Void
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        HStack(spacing: 4) {
            if showBack {
                Button(action: onBack) {
                    Image(systemName: "arrow.backward").font(.system(size: 19, weight: .semibold))
                        .foregroundColor(Brand.ink).frame(width: 44, height: 44)
                }
                .accessibilityLabel("رجوع")
            } else {
                Spacer().frame(width: 12)
            }
            Text(title).font(T.titleLarge).foregroundColor(Brand.ink).lineLimit(1)
            Spacer(minLength: 4)
            actions()
        }
        .padding(.trailing, 8)
        .frame(height: 56)
        .background(Brand.bg)
    }
}

struct Fab {
    let label: String
    let action: () -> Void
}

/// Standard screen frame: top bar + scrolling content with comfortable padding.
struct ScreenList<Content: View, Actions: View>: View {
    let title: String
    var fab: Fab? = nil
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content
    @Environment(\.canGoBack) var canGoBack
    @EnvironmentObject var router: Router

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: title, showBack: canGoBack, onBack: { router.back() }, actions: actions)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) { content() }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 96)
            }
        }
        .background(Brand.bg.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            if let fab = fab { AddFab(label: fab.label, action: fab.action).padding(16) }
        }
    }
}

extension ScreenList where Actions == EmptyView {
    init(title: String, fab: Fab? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.fab = fab
        self.actions = { EmptyView() }
        self.content = content
    }
}

struct AddFab: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                Text(label).font(T.labelLarge)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Brand.maroon))
            .shadow(color: Brand.maroon.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Gradient header used on every home screen.
struct HomeHeader: View {
    let greeting: String
    let title: String
    let subtitle: String
    let unread: Int
    let onBell: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    SwiftUI.Circle().fill(Color.white)
                    Image("Logo").resizable().scaledToFit().frame(width: 40, height: 40).clipShape(SwiftUI.Circle())
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 0) {
                    Text(greeting).font(T.bodySmall).foregroundColor(.white.opacity(0.75))
                    Text(title).font(T.titleLarge).foregroundColor(.white).lineLimit(1)
                }
                Spacer()
                Button(action: onBell) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell").font(.system(size: 19)).foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(SwiftUI.Circle().fill(Color.white.opacity(0.12)))
                        if unread > 0 {
                            Text("\(unread)").font(AppFont.f(10, .bold)).foregroundColor(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(SwiftUI.Circle().fill(Brand.maroon))
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .accessibilityLabel("الإشعارات")
            }
            Spacer().frame(height: 14)
            Text(subtitle).font(T.bodyMedium).foregroundColor(.white.opacity(0.85))
            OccasionCard().padding(.top, 12)
            SyncLine().padding(.top, 10)
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 26)
        .background(
            LinearGradient(colors: [Brand.navy, Brand.navyMid, Brand.navyDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedCorners(radius: 30, corners: [.bottomLeft, .bottomRight]))
                .ignoresSafeArea(edges: .top)
        )
    }
}

struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

/// Centred card dialog (the Android AlertDialog look).
struct DialogCard<Content: View, Buttons: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var buttons: () -> Buttons
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(T.titleLarge).foregroundColor(Brand.ink)
            content()
            HStack(spacing: 8) {
                Spacer()
                buttons()
            }
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Brand.card))
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 10)
        .padding(.horizontal, 24)
    }
}

struct DialogButton: View {
    let title: String
    var filled = false
    var color: Color = Brand.navy
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(T.labelLarge)
                .foregroundColor(filled ? .white : (enabled ? color : Brand.muted))
                .padding(.horizontal, 18).frame(height: 40)
                .background(Capsule().fill(filled ? (enabled ? color : Brand.muted.opacity(0.35)) : Color.clear))
        }
        .disabled(!enabled)
    }
}

struct ConfirmDialog: View {
    let title: String
    let message: String
    let confirm: String
    var destructive = false
    let onConfirm: () -> Void
    @EnvironmentObject var dialogs: DialogHost
    var body: some View {
        DialogCard(title: title) {
            Text(message).font(T.bodyMedium).foregroundColor(Brand.muted)
        } buttons: {
            DialogButton(title: "إلغاء") { dialogs.dismiss() }
            DialogButton(title: confirm, filled: true, color: destructive ? Brand.red : Brand.navy) { onConfirm(); dialogs.dismiss() }
        }
    }
}

/// Simple picker dialog for choosing one item from a list.
struct PickerDialog<Item>: View {
    let title: String
    let items: [Item]
    let label: (Item) -> String
    var searchable = false
    let onPick: (Item) -> Void
    @State private var q = ""
    @EnvironmentObject var dialogs: DialogHost
    var body: some View {
        let needle = q.trimmingCharacters(in: .whitespaces)
        let shown = items.enumerated().filter { needle.isEmpty || label($0.element).contains(needle) }
        DialogCard(title: title) {
            VStack(spacing: 8) {
                if searchable { SearchField(placeholder: "بحث", text: $q) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown, id: \.offset) { pair in
                            Button {
                                onPick(pair.element)
                                dialogs.dismiss()
                            } label: {
                                Text(label(pair.element)).font(T.bodyLarge).foregroundColor(Brand.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 12).padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        } buttons: {
            DialogButton(title: "إغلاق") { dialogs.dismiss() }
        }
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text).font(T.bodyMedium).foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x2F2E3E)))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 16)
    }
}
