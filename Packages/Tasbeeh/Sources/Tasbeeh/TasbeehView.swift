import SwiftUI
import UIKit

/// Screen state that is not saved (the bead flow, sheets, the scene on screen).
final class TsbScreen: ObservableObject {
    let flow = TsbFlow()
    @Published var markerBase: Double = 0
    @Published var scene: CineScene = Cine.savedScene()
    @Published var showSheet = false
    @Published var showScenes = false
    @Published var muted = CineAudio.shared.muted
    @Published var entered = false
    @Published var textH: CGFloat = 0
    @Published var confirmAll = false
    var started = false
}

private struct TsbTextH: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// «المسبحة» — cinematic version: a full-screen moving scene (bundled, offline), a thin breathing string of glass beads that
/// glides one bead per tap, glass ticks + a soft cue at the end of each round, and the scene's ambient sound.
///
/// Push it from a NavigationLink, or wrap it in a NavigationStack for a sheet / fullScreenCover.
public struct TasbeehView: View {
    @StateObject private var m = TasbeehModel()
    @StateObject private var s = TsbScreen()

    public init() { Cine.registerFonts() }

    public var body: some View {
        GeometryReader { outer in
          let win = CineSafe.window
          let top = max(outer.safeAreaInsets.top, win.top + 44)
          let bottom = max(outer.safeAreaInsets.bottom, win.bottom)
          GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let cyR: CGFloat = 0.47
            let cy = H * cyR
            let regTop = top + 8
            let bandTop = cy - W * 0.075
            let region = max(bandTop - regTop, 80)
            let th = s.textH > 0 ? s.textH : 180
            let tsc = th > region ? max(region / th, 0.72) : 1
            let ty = regTop + max(region - th * tsc, 0) * 0.3
            let counterTop = cy + W * 0.052 + 80 - 55.5
            let counterBottom = counterTop + TsbCounter.boxH
            let statsY = min(max(H - bottom - 70, counterBottom + 30), H - bottom - 30)
            ZStack(alignment: .top) {
                Color(red: 0.01, green: 0.015, blue: 0.03)
                CineBackground(scene: s.scene).id(s.scene.id).transition(.opacity)
                CineScrim()
                // tap anywhere to count
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: tap)
                TsbSceneCanvas(flow: s.flow, markerBase: s.markerBase, target: m.target, cyRatio: cyR)
                    .frame(width: W, height: H)
                    .opacity(s.entered ? 1 : 0)
                textBlock
                    .frame(width: max(W - 44, 100))
                    .background(GeometryReader { g in Color.clear.preference(key: TsbTextH.self, value: g.size.height) })
                    .scaleEffect(tsc, anchor: .top)
                    .padding(.top, ty)
                    .animation(.easeInOut(duration: 0.3), value: ty)
                    .opacity(s.entered ? 1 : 0)
                    .offset(y: s.entered ? 0 : -14)
                TsbCounter(flow: s.flow, count: m.count, target: m.target)
                    .frame(width: TsbCounter.boxW, height: TsbCounter.boxH, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: tap)
                    .onLongPressGesture(minimumDuration: 0.5) { s.showSheet = true }
                    .scaleEffect(s.entered ? 1 : 0.9)
                    .frame(width: W)
                    .padding(.top, counterTop)
                    .opacity(s.entered ? 1 : 0)
                Button { s.showSheet = true } label: {
                    HStack(spacing: 5) {
                        Text(verbatim: "الدورات")
                        Text(verbatim: Cine.num(m.rounds)).fontWeight(.semibold)
                        Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 12).padding(.horizontal, 6)
                        Text(verbatim: "المجموع")
                        Text(verbatim: Cine.num(m.total)).fontWeight(.semibold)
                    }
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundColor(.white.opacity(0.84))
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.26)))
                }
                .buttonStyle(.plain)
                .frame(width: W)
                .padding(.top, statsY - 18)
                .opacity(s.entered ? 1 : 0)
            }
            .frame(width: W, height: H)
            .onPreferenceChange(TsbTextH.self) { v in if abs(v - s.textH) > 0.5 { s.textH = v } }
          }
          .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .rightToLeft)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { s.showScenes = true } label: {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                }
                .accessibilityLabel(Text(verbatim: "الخلفية"))
                Button { s.muted.toggle(); CineAudio.shared.muted = s.muted } label: {
                    Image(systemName: s.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                }
                .accessibilityLabel(Text(verbatim: s.muted ? "تشغيل الصوت" : "كتم الصوت"))
                Button { s.showSheet = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                }
                .accessibilityLabel(Text(verbatim: "الخيارات"))
            }
        }
        .sheet(isPresented: $s.showSheet) {
            TsbOptionsSheet(m: m, onSelect: { i in select(i) }, onTarget: { s.markerBase = s.flow.to - Double(m.count) },
                            onReset: { s.markerBase = s.flow.to })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $s.showScenes) {
            CineScenePicker(current: s.scene.id) { sc in pickScene(sc) }
                .presentationDetents([.large])
        }
        .onAppear(perform: start)
        .onDisappear { CineAudio.shared.leave(); s.started = false }
    }

    private var sel: Int { min(max(m.selected, 0), TasbeehModel.phrases.count - 1) }

    private var textBlock: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(verbatim: TasbeehModel.phrases[sel].text)
                    .font(.custom("Amiri-Regular", size: sel == 8 ? 30 : 42))
                    .lineLimit(3).minimumScaleFactor(0.5)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 3)
                Circle().fill(Cine.warm).frame(width: 5, height: 5)
                    .shadow(color: Cine.warm.opacity(0.9), radius: 4)
                    .padding(.top, 8).padding(.bottom, 10)
                Text(verbatim: TasbeehModel.phrases[sel].ref)
                    .font(.system(size: 13, weight: .medium)).opacity(0.62)
                    .shadow(color: .black.opacity(0.5), radius: 5, y: 1)
            }
            .id(sel)
            .transition(.opacity)
            HStack(spacing: 7) {
                ForEach(0..<TasbeehModel.phrases.count, id: \.self) { i in
                    Circle().fill(Color.white.opacity(i == sel ? 0.85 : 0.25)).frame(width: i == sel ? 6 : 5, height: i == sel ? 6 : 5)
                        .frame(width: 14, height: 20).contentShape(Rectangle())
                        .onTapGesture { select(i) }
                }
            }
            .padding(.top, 12)
        }
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            guard abs(v.translation.width) > 44, abs(v.translation.width) > abs(v.translation.height) else { return }
            let n = TasbeehModel.phrases.count
            // right-to-left: a swipe to the right shows the next dhikr
            select((sel + (v.translation.width > 0 ? 1 : n - 1)) % n)
        })
    }

    private func start() {
        guard !s.started else { return }
        s.started = true
        CineAudio.shared.prepare()
        CineAudio.shared.ambient(Cine.ambient(s.scene))
        s.flow.enter()
        s.markerBase = s.flow.to - Double(m.count)
        withAnimation(.easeOut(duration: 0.6)) { s.entered = true }
    }

    private func select(_ i: Int) {
        guard m.selected != i else { return }
        withAnimation(.easeInOut(duration: 0.35)) { m.select(i) }
        s.markerBase = s.flow.to - Double(m.count)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func tap() {
        let reached = m.tap()
        s.flow.tap()
        if reached {
            s.flow.done = TsbFlow.now()
            s.markerBase = s.flow.to
            CineAudio.shared.complete()
            if m.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        } else {
            CineAudio.shared.tap()
            if m.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }

    private func pickScene(_ sc: CineScene) {
        withAnimation(.easeInOut(duration: 0.6)) { s.scene = sc }
        Cine.save(sc)
        CineAudio.shared.ambient(Cine.ambient(sc))
    }
}

/// Options: dhikr list, target (33 / 99 / 100 / custom), vibration, totals, reset — kept off the main screen.
struct TsbOptionsSheet: View {
    @ObservedObject var m: TasbeehModel
    let onSelect: (Int) -> Void
    let onTarget: () -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let warm = Color(red: 0.98, green: 0.66, blue: 0.36)

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 38, height: 5).padding(.top, 8)
                Text(verbatim: "المسبحة").font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                VStack(spacing: 8) {
                    ForEach(0..<TasbeehModel.phrases.count, id: \.self) { i in
                        let on = m.selected == i
                        Button { onSelect(i); dismiss() } label: {
                            HStack(spacing: 12) {
                                Circle().fill(on ? warm : Color.white.opacity(0.18)).frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: TasbeehModel.phrases[i].text).font(.custom("Amiri-Regular", size: 20)).foregroundColor(.white)
                                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    Text(verbatim: TasbeehModel.phrases[i].ref).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.55))
                                }
                                Spacer(minLength: 0)
                                Text(verbatim: Cine.num(m.counts[i])).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.white.opacity(on ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(TasbeehModel.presetTargets, id: \.self) { v in
                        targetChip(Cine.num(v), on: m.target == v) { m.target = v; onTarget() }
                    }
                    targetChip(m.isCustomTarget ? Cine.num(m.target) : "مخصص", on: m.isCustomTarget) { m.customOpen = true }
                }
                Button { m.haptics.toggle() } label: {
                    HStack {
                        Image(systemName: m.haptics ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                        Text(verbatim: m.haptics ? "الاهتزاز: شغّال" : "الاهتزاز: مقفّل")
                        Spacer()
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                HStack(spacing: 10) {
                    stat("العدد", m.count); stat("الدورات", m.rounds); stat("المجموع", m.total)
                }
                HStack(spacing: 10) {
                    Button { m.resetCurrent(); onReset(); dismiss() } label: {
                        Text(verbatim: "تصفير").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button { m.resetOpen = true } label: {
                        Text(verbatim: "تصفير كل العدّادات").font(.system(size: 15, weight: .semibold)).foregroundColor(Color(red: 1, green: 0.42, blue: 0.42))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 20)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .rightToLeft)
        .alert(Text(verbatim: "عدد مخصص"), isPresented: $m.customOpen) {
            TextField(text: $m.customText) { Text(verbatim: "مثال: 1000") }
                .keyboardType(.numberPad)
            Button(role: .cancel) { m.customText = "" } label: { Text(verbatim: "إلغاء") }
            Button { m.applyCustom(); onTarget() } label: { Text(verbatim: "حفظ") }
        }
        .alert(Text(verbatim: "تصفير كل العدّادات؟"), isPresented: $m.resetOpen) {
            Button(role: .cancel) {} label: { Text(verbatim: "إلغاء") }
            Button(role: .destructive) { m.resetAll(); onReset(); dismiss() } label: { Text(verbatim: "تصفير") }
        }
    }

    private func targetChip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(on ? .black : .white)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(on ? warm : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func stat(_ title: String, _ n: Int) -> some View {
        VStack(spacing: 3) {
            Text(verbatim: Cine.num(n)).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(verbatim: title).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity).frame(height: 62)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
