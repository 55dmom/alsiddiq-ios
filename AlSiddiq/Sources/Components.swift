import SwiftUI

struct AppCard<Content: View>: View {
    var padding: CGFloat = 16
    var onTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let card = VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Brand.card))
            .shadow(color: Brand.navy.opacity(0.08), radius: 8, x: 0, y: 3)
        if let onTap = onTap {
            Button(action: onTap) { card }.buttonStyle(PressableStyle())
        } else {
            card
        }
    }
}

/// Soft press feedback for tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var enabled = true
    var height: CGFloat = 52
    var color: Color = Brand.navy
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(.white) }
                else {
                    if let icon = icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)) }
                    Text(title).font(T.titleMedium)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(enabled ? color : Brand.muted.opacity(0.35)))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled || busy)
    }
}

struct OutlineButton: View {
    let title: String
    var icon: String? = nil
    var enabled = true
    var height: CGFloat = 48
    var color: Color = Brand.navy
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(T.labelLarge)
            }
            .foregroundColor(enabled ? color : Brand.muted)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.line, lineWidth: 1.2).background(Brand.card.cornerRadius(14)))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

struct TextAction: View {
    let title: String
    var color: Color = Brand.maroon
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(T.labelLarge).foregroundColor(color).padding(.vertical, 8).padding(.horizontal, 6) }
    }
}

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title).font(T.titleMedium).foregroundColor(Brand.ink)
            Spacer()
            if let action = action, let onAction = onAction { TextAction(title: action, action: onAction) }
        }
        .padding(.top, 18).padding(.bottom, 8)
    }
}

struct IconBadge: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 40
    var corner: CGFloat = 12
    var circle = false
    var bgOpacity = 0.12
    /// v3.8: an illustrated picture from the asset catalog («art_<name>»); the SF Symbol stays as the fallback.
    var art: String? = nil
    var body: some View {
        ZStack {
            if circle { SwiftUI.Circle().fill(tint.opacity(bgOpacity)) }
            else { RoundedRectangle(cornerRadius: corner, style: .continuous).fill(tint.opacity(bgOpacity)) }
            if let a = art, let ui = UIImage(named: "art_" + a) {
                Image(uiImage: ui).resizable().scaledToFit().padding(size * 0.08)
            } else {
                Image(systemName: icon).font(.system(size: size * 0.48, weight: .medium)).foregroundColor(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

/// v3.8: which illustrated picture goes with a button, by its title (the same set as the Android app).
enum ArtIcon {
    static func forTitle(_ t: String) -> String? {
        let map: [(String, String)] = [
            ("حضور وغياب المعلمين", "teacher_attendance"), ("كشف الاشتراكات", "subscriptions"), ("الميزانية", "budget"),
            ("طالب جديد", "add_student"), ("حلقة جديدة", "add_circle"), ("تسميع", "tasmee"), ("تسجيل", "record"),
            ("الحضور", "attendance"), ("حضور اليوم", "attendance"), ("تحضير", "attendance"),
            ("الطلاب", "students"), ("طلاب الحلقة", "students"), ("الحلقات", "circles"), ("المعلمون", "teachers"), ("المعلمين", "teachers"),
            ("التقارير", "reports"), ("تقرير اليوم", "reports"), ("الإعلانات", "announcement"), ("المتفوقون", "honors"),
            ("المكافآت", "honors"), ("وسام الشرف", "weekly_star"), ("عن المركز", "about"), ("تواصل مع المطوّر", "developer"),
            ("الثيمات", "themes"), ("الأدوات", "tools"), ("الإدارة", "admin"), ("كلمات السر", "admin"), ("الإعدادات", "settings"),
            ("الإشعارات", "bell"), ("بيانات المركز", "about"), ("عن التطبيق", "about"),
        ]
        return map.first { t.hasPrefix($0.0) }?.1
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let icon: String
    let tint: Color
    var sub: String? = nil
    var onTap: (() -> Void)? = nil
    var body: some View {
        AppCard(padding: 14, onTap: onTap) {
            IconBadge(icon: icon, tint: tint, size: 38, art: ArtIcon.forTitle(label))
            Spacer().frame(height: 10)
            Text(value).font(T.headlineSmall).foregroundColor(Brand.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(T.bodySmall).foregroundColor(Brand.muted).lineLimit(1)
            if let sub = sub { Text(sub).font(T.labelSmall).foregroundColor(tint).lineLimit(1) }
        }
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 44
    var color: Color = Brand.navy
    var initials: String {
        let skip: Set<String> = ["الشيخ", "الأستاذ"]
        var out = ""
        var n = 0
        for part in name.split(separator: " ") {
            let w = String(part)
            if w.isEmpty || skip.contains(w) { continue }
            if let c = w.first { out.append(c) }
            n += 1
            if n == 2 { break }
        }
        return out
    }
    var body: some View {
        ZStack {
            SwiftUI.Circle().fill(color.opacity(0.12))
            Text(initials).font(AppFont.f(size * 0.36, .bold)).foregroundColor(color)
        }
        .frame(width: size, height: size)
    }
}

/// A student's round photo, or their initial when there is none (v3.1).
struct StudentAvatar: View {
    let s: Student
    var size: CGFloat = 44
    var color: Color = Brand.navy
    @EnvironmentObject var model: AppModel
    @State private var img: UIImage?
    var body: some View {
        ZStack {
            if let img = img {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(SwiftUI.Circle())
                    .overlay(SwiftUI.Circle().stroke(Brand.gold.opacity(0.55), lineWidth: 1.5))
            } else {
                Avatar(name: s.fullName, size: size, color: color)
            }
        }
        .frame(width: size, height: size)
        .task(id: s.photoPath ?? "-") {
            if s.photoPath == nil { img = nil; return }
            img = await model.repo.photo(s)
        }
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var filled = false
    var body: some View {
        Text(text).font(T.labelMedium).lineLimit(1)
            .foregroundColor(filled ? .white : color)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(filled ? color : color.opacity(0.12)))
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                SwiftUI.Circle().fill(Brand.navySoft)
                Image(systemName: "tray").font(.system(size: 30)).foregroundColor(Brand.navy)
            }.frame(width: 72, height: 72)
            Spacer().frame(height: 14)
            Text(title).font(T.titleMedium).foregroundColor(Brand.ink).multilineTextAlignment(.center)
            if !message.isEmpty {
                Spacer().frame(height: 4)
                Text(message).font(T.bodyMedium).foregroundColor(Brand.muted).multilineTextAlignment(.center)
            }
            if let action = action, let onAction = onAction {
                Spacer().frame(height: 14)
                Button(action: onAction) {
                    Text(action).font(T.labelLarge).foregroundColor(.white).padding(.horizontal, 22).padding(.vertical, 10)
                        .background(Capsule().fill(Brand.navy))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

struct DemoBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash.fill").font(.system(size: 15)).foregroundColor(Brand.gold)
            Text("وضع تجريبي: البيانات محفوظة على هذا الجهاز فقط ولا تتم مزامنتها بعد")
                .font(T.labelMedium).foregroundColor(Brand.goldInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.goldSoft))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.gold.opacity(0.4), lineWidth: 1))
    }
}

/// Animated circular progress with the value in the middle.
struct ProgressRing<Center: View>: View {
    let progress: Double
    var size: CGFloat = 120
    var stroke: CGFloat = 12
    var color: Color = Brand.navy
    var track: Color = Brand.navySoft
    @ViewBuilder var center: () -> Center
    @State private var shown: Double = 0
    var body: some View {
        ZStack {
            SwiftUI.Circle().stroke(track, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            SwiftUI.Circle().trim(from: 0, to: CGFloat(shown))
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .padding(stroke / 2)
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = min(max(progress, 0), 1) } }
        .onChange(of: progress) { v in withAnimation(.easeOut(duration: 0.6)) { shown = min(max(v, 0), 1) } }
    }
}

struct BarDatum: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let detail: String
}

/// Interactive bar chart: tap a bar to see its value. Oldest first (on the right in RTL), like Android.
struct BarChart: View {
    let data: [BarDatum]
    var height: CGFloat = 160
    var color: Color = Brand.navy
    var highlight: Color = Brand.maroon
    @State private var selected: Int? = nil
    @State private var grow: CGFloat = 0

    var body: some View {
        let maxV = max(data.map { $0.value }.max() ?? 1, 1)
        let sel = min(selected ?? (data.count - 1), max(data.count - 1, 0))
        VStack(alignment: .leading, spacing: 10) {
            if data.indices.contains(sel) {
                HStack(spacing: 8) {
                    Pill(text: data[sel].label, color: highlight)
                    Text(data[sel].detail).font(T.titleSmall).foregroundColor(Brand.ink)
                }
            }
            GeometryReader { geo in
                let slot = geo.size.width / CGFloat(max(data.count, 1))
                let barW = slot * 0.56
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(data.enumerated()), id: \.offset) { i, d in
                        let h = CGFloat(d.value / maxV) * (geo.size.height - 8) * grow
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Brand.line.opacity(0.45)).frame(width: barW, height: geo.size.height)
                            Capsule().fill(i == sel ? highlight : color).frame(width: barW, height: h)
                        }
                        .frame(width: slot, height: geo.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { selected = i } }
                    }
                }
            }
            .frame(height: height)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { grow = 1 } }
    }
}

struct Slice: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

struct DonutChart: View {
    let slices: [Slice]
    var size: CGFloat = 130
    var centerText = ""
    @State private var sweep: CGFloat = 0
    @State private var selected: Int? = nil

    var body: some View {
        let total = slices.reduce(0) { $0 + $1.value }
        HStack(spacing: 16) {
            ZStack {
                if total <= 0 {
                    SwiftUI.Circle().stroke(Brand.line, lineWidth: 22).padding(11)
                } else {
                    let fr = fractions(total)
                    ForEach(Array(slices.enumerated()), id: \.offset) { i, s in
                        let a: CGFloat = fr[i].0 * sweep
                        let b: CGFloat = max(a, fr[i].1 * sweep - 0.004)
                        let w: CGFloat = selected == i ? 27 : 22
                        SwiftUI.Circle()
                            .trim(from: a, to: b)
                            .stroke(s.color, lineWidth: w)
                            .rotationEffect(.degrees(-90))
                            .padding(13.5)
                    }
                }
                Text(selected.map { i in total > 0 ? "\(Int((slices[i].value / total * 100).rounded()))%" : centerText } ?? centerText)
                    .font(T.titleLarge).foregroundColor(Brand.ink)
            }
            .frame(width: size, height: size)
            VStack(spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.offset) { i, s in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { selected = selected == i ? nil : i }
                    } label: {
                        HStack(spacing: 8) {
                            SwiftUI.Circle().fill(s.color).frame(width: 10, height: 10)
                            Text(s.label).font(T.bodySmall).foregroundColor(Brand.ink)
                            Spacer()
                            Text("\(Int(s.value.rounded()))").font(T.labelLarge).foregroundColor(Brand.muted)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selected == i ? s.color.opacity(0.08) : .clear))
                    }
                }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { sweep = 1 } }
    }
}

extension DonutChart {
    func fractions(_ total: Double) -> [(CGFloat, CGFloat)] {
        var out: [(CGFloat, CGFloat)] = []
        var acc = 0.0
        for s in slices {
            let start = acc / total
            acc += s.value
            out.append((CGFloat(start), CGFloat(acc / total)))
        }
        return out
    }
}

struct LinearMeter: View {
    let progress: Double
    let color: Color
    @State private var shown: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.12))
                Capsule().fill(color).frame(width: geo.size.width * shown)
            }
        }
        .frame(height: 8)
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { shown = CGFloat(min(max(progress, 0), 1)) } }
        .onChange(of: progress) { v in withAnimation(.easeOut(duration: 0.5)) { shown = CGFloat(min(max(v, 0), 1)) } }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(key).font(T.bodyMedium).foregroundColor(Brand.muted)
            Spacer()
            Text(value).font(AppFont.f(14, .medium)).foregroundColor(Brand.ink).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }
}

struct MiniStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(T.titleLarge).foregroundColor(Brand.navy).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(T.labelSmall).foregroundColor(Brand.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ChoiceChips: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                    let sel = i == selected
                    Button { withAnimation(.easeOut(duration: 0.18)) { onSelect(i) } } label: {
                        HStack(spacing: 4) {
                            if sel { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                            Text(o).font(T.labelLarge)
                        }
                        .foregroundColor(sel ? .white : Brand.ink)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(sel ? Brand.navy : Brand.card))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(sel ? Brand.navy : Brand.line, lineWidth: 1))
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct Field: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var multiline = false
    var minLines = 1
    var secure = false
    @State private var reveal = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(T.labelSmall).foregroundColor(Brand.muted)
            HStack {
                Group {
                    if secure && !reveal {
                        SecureField("", text: $text)
                    } else if multiline {
                        TextEditorBox(text: $text, minLines: minLines)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .font(T.bodyLarge)
                .keyboardType(keyboard)
                .disableAutocorrection(keyboard != .default)
                if secure {
                    Button { reveal.toggle() } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye").foregroundColor(Brand.muted)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, multiline ? 8 : 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.line, lineWidth: 1.2))
        }
    }
}

/// A multi-line text box that grows, without TextEditor's grey background on iOS 15.
struct TextEditorBox: View {
    @Binding var text: String
    var minLines: Int
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text.isEmpty ? " " : text).font(T.bodyLarge).opacity(0)
                .frame(maxWidth: .infinity, minHeight: CGFloat(minLines) * 24, alignment: .topLeading)
                .padding(.vertical, 8)
            TextEditor(text: $text)
                .font(T.bodyLarge)
                .onAppear { UITextView.appearance().backgroundColor = .clear }
        }
    }
}

struct SelectorField: View {
    let label: String
    let value: String
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(T.labelSmall).foregroundColor(Brand.muted)
                HStack {
                    Text(value).font(T.bodyLarge).foregroundColor(Brand.ink).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundColor(Brand.muted)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.line, lineWidth: 1.2))
        }
        .buttonStyle(PressableStyle())
    }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Brand.muted)
            TextField(placeholder, text: $text).font(T.bodyLarge).disableAutocorrection(true)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Brand.muted) }
            }
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.line, lineWidth: 1.2))
    }
}

struct Divider1: View {
    var body: some View { Rectangle().fill(Brand.line).frame(height: 1) }
}

struct AssistChip: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(T.labelLarge).foregroundColor(Brand.ink)
                .padding(.horizontal, 14).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Brand.line, lineWidth: 1))
        }
    }
}

/// v3.2: the sync status line (writes waiting on the phone, waiting for a password, or refused).
struct SyncLine: View {
    @EnvironmentObject var model: AppModel
    var onDark = true
    var body: some View {
        if let i = info {
            HStack(spacing: 8) {
                Image(systemName: i.1).font(.system(size: 13, weight: .semibold)).foregroundColor(i.2)
                Text(i.0).font(T.labelMedium).foregroundColor(onDark ? .white : Brand.ink).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(onDark ? Color.white.opacity(0.12) : Brand.goldSoft))
            .accessibilityIdentifier("syncLine")
        }
    }
    private var info: (String, String, Color)? {
        switch model.sync {
        case .pending(let n): return ("بانتظار الإرسال: \(n) • تُرسل تلقائياً عند عودة الإنترنت", "icloud.and.arrow.up", Brand.gold)
        case .waitingPassword(let n, let r):
            return ("\(n) محفوظة على الجهاز • اكتب كلمة سر \(r == .admin ? "الإدارة" : "المعلمين") لإرسالها", "lock.icloud", Brand.gold)
        case .error(let m): return (m, "exclamationmark.icloud", Brand.red)
        default: return nil
        }
    }
}

/// The centre's ORIGINAL logo (never redrawn), shown wholly inside a circle: a white disc with the logo
/// scaled to fit inside it with padding, clipped round, so no square corner shows past the circle.
/// Measured on logo.jpg (640x640, white background): every inked pixel, the name text included, lies within
/// 0.528 of the image side from a point 5.5% of the side above the image centre; `side` is chosen so that
/// circle sits `padding` inside the disc.
struct RoundLogo: View {
    var diameter: CGFloat
    var padding: CGFloat
    var body: some View {
        let side = max(0, (diameter / 2 - padding) / 0.528)
        ZStack {
            SwiftUI.Circle().fill(Color.white)
            Image("Logo").resizable().scaledToFit()
                .frame(width: side, height: side)
                // logo.jpg's first pixel column is a grey hairline; trim it so no line shows on the white disc
                .clipShape(Rectangle().inset(by: side * 0.004))
                .offset(y: -side * 0.055)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(SwiftUI.Circle())
    }
}
