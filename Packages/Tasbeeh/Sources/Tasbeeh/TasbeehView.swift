import SwiftUI

/// «المسبحة» — the button's single entry view.
///
/// Push it from a NavigationLink, or wrap it in a NavigationStack for a sheet.
public struct TasbeehView: View {
    @StateObject private var m = TasbeehModel()
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                phraseCard
                counter
                targetRow
                statsRow
                phraseList
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(TsbTheme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "المسبحة"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { m.haptics.toggle() } label: {
                    Image(systemName: m.haptics ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                }
                .accessibilityLabel(Text(verbatim: m.haptics ? "إيقاف الاهتزاز" : "تشغيل الاهتزاز"))
            }
        }
        .alert(Text(verbatim: "عدد مخصص"), isPresented: $m.customOpen) {
            TextField(text: $m.customText) { Text(verbatim: "مثال: 1000") }
                .keyboardType(.numberPad)
            Button(role: .cancel) { m.customText = "" } label: { Text(verbatim: "إلغاء") }
            Button { m.applyCustom() } label: { Text(verbatim: "حفظ") }
        } message: {
            Text(verbatim: "اكتب العدد اللي تبي توصله")
        }
        .confirmationDialog(Text(verbatim: "تصفير العداد"), isPresented: $m.resetOpen, titleVisibility: .visible) {
            Button(role: .destructive) { m.resetCurrent() } label: { Text(verbatim: "تصفير هذا الذكر") }
            Button(role: .destructive) { m.resetAll() } label: { Text(verbatim: "تصفير الكل والمجموع") }
            Button(role: .cancel) {} label: { Text(verbatim: "إلغاء") }
        }
        .tint(TsbTheme.accent)
        .tsbRTL()
    }

    private var phraseCard: some View {
        TsbCard {
            VStack(spacing: 8) {
                Text(verbatim: m.phrase.text)
                    .font(.system(size: 26, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: m.phrase.ref)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var counter: some View {
        Button {
            let reached = m.tap()
            if m.haptics { reached ? TsbHaptics.success() : TsbHaptics.tap() }
        } label: {
            ZStack {
                Circle().fill(TsbTheme.card)
                Circle().stroke(TsbTheme.line, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: m.progress)
                    .stroke(TsbTheme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: m.progress)
                VStack(spacing: 4) {
                    Text(verbatim: "\(m.count)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    Text(verbatim: "من \(m.target)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(verbatim: "اضغط للتسبيح")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 270, height: 270)
            .contentShape(Circle())
        }
        .buttonStyle(TsbPressStyle())
        .accessibilityLabel(Text(verbatim: "العداد \(m.count) من \(m.target)"))
        .padding(.vertical, 6)
    }

    private var targetRow: some View {
        TsbCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "الهدف").font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach(TasbeehModel.presetTargets, id: \.self) { t in
                        chip("\(t)", on: m.target == t) { m.target = t }
                    }
                    chip(m.isCustomTarget ? "\(m.target)" : "مخصص", on: m.isCustomTarget) { m.customOpen = true }
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            stat(title: "الجولات", value: m.rounds)
            stat(title: "المجموع", value: m.total)
            Button { m.resetOpen = true } label: {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise").font(.title3)
                    Text(verbatim: "تصفير").font(.footnote)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(TsbTheme.card))
            }
            .buttonStyle(.plain)
            .foregroundColor(TsbTheme.accent)
        }
    }

    private var phraseList: some View {
        TsbCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "الأذكار").font(.subheadline.weight(.semibold)).padding(.bottom, 4)
                ForEach(TasbeehModel.phrases) { p in
                    Button { m.select(p.id) } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: m.selected == p.id ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(m.selected == p.id ? TsbTheme.accent : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: p.text)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: p.ref).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                            if m.counts[p.id] > 0 {
                                Text(verbatim: "\(m.counts[p.id])")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if p.id != TasbeehModel.phrases.count - 1 { Divider() }
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(on ? TsbTheme.accent : TsbTheme.soft))
                .foregroundColor(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func stat(title: String, value: Int) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: "\(value)").font(.title3.weight(.bold)).monospacedDigit()
            Text(verbatim: title).font(.footnote).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(TsbTheme.card))
    }
}

private struct TsbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
