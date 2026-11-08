import SwiftUI
import UIKit

/// Needle state + saved position. Each tap glides the red needle to the next name (0.46 s, slight overshoot).
final class AsmaModel: ObservableObject {
    private let d = UserDefaults.standard
    private let k = "alsalmi.asma."
    @Published var idx: Int
    @Published var done: Bool
    @Published var scene: CineScene = Cine.savedScene()
    @Published var showScenes = false
    @Published var muted = CineAudio.shared.muted
    @Published var showList = false
    var from = 0.0, to = 0.0, t0 = -100.0, dur = 0.46
    var pulseAt = -100.0, doneAt = -100.0
    var started = false
    private let light = UIImpactFeedbackGenerator(style: .light)
    static let count = AsmaData.names.count

    init() {
        idx = min(max(UserDefaults.standard.integer(forKey: "alsalmi.asma.idx"), 0), AsmaModel.count - 1)
        done = UserDefaults.standard.bool(forKey: "alsalmi.asma.done")
        from = Double(idx); to = from
    }
    static var now: Double { Date().timeIntervalSinceReferenceDate }
    static func ease(_ p: Double) -> Double { let c1 = 1.25, c3 = c1 + 1, q = p - 1; return 1 + c3 * q * q * q + c1 * q * q }
    func pos(_ t: Double) -> Double { let p = min(max((t - t0) / dur, 0), 1); return from + (to - from) * AsmaModel.ease(p) }
    private func go(_ target: Double, _ dd: Double = 0.46) { let t = AsmaModel.now; from = pos(t); to = target; t0 = t; dur = dd }
    func save() { d.set(idx, forKey: k + "idx"); d.set(done, forKey: k + "done") }
    func enter() { let t = AsmaModel.now; from = to - 6; t0 = t; dur = 1.1 }

    func next() {
        let t = AsmaModel.now
        if done {
            withAnimation(.easeOut(duration: 0.3)) { done = false; idx = 0 }
            go(0, 1.25); CineAudio.shared.tap(); light.impactOccurred(intensity: 0.7)
        } else if idx >= AsmaModel.count - 1 {
            withAnimation(.easeOut(duration: 0.3)) { done = true }
            doneAt = t; pulseAt = t; CineAudio.shared.complete(); UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            withAnimation(.easeOut(duration: 0.3)) { idx += 1 }
            go(Double(idx)); pulseAt = t; CineAudio.shared.tap(); light.impactOccurred(intensity: 0.7)
        }
        save()
    }
    func prev() {
        if done { withAnimation(.easeOut(duration: 0.3)) { done = false }; CineAudio.shared.tap(); light.impactOccurred(intensity: 0.7) }
        else if idx > 0 { withAnimation(.easeOut(duration: 0.3)) { idx -= 1 }; go(Double(idx)); CineAudio.shared.tap(); light.impactOccurred(intensity: 0.7) }
        save()
    }
    func jump(_ i: Int) {
        let i2 = min(max(i, 0), AsmaModel.count - 1)
        withAnimation(.easeOut(duration: 0.3)) { done = false; idx = i2 }
        go(Double(i2), 0.9); pulseAt = AsmaModel.now; CineAudio.shared.tap(); save()
    }
}

enum AsmaUI {
    static let red = Color(red: 0.898, green: 0.137, blue: 0.239)
    static let redHi = Color(red: 1.0, green: 0.353, blue: 0.306)
}

/// «أسماء الله الحسنى» — cinematic version: a translucent dark dial with 99 ticks and the names around it over a moving scene
/// (bundled, offline). Each tap glides the red needle to the next name with a glass tick; the end of the 99 plays a soft cue.
///
/// Push it from a NavigationLink, or wrap it in a NavigationStack for a sheet / fullScreenCover.
public struct AsmaAllahView: View {
    @StateObject private var m = AsmaModel()

    public init() { Cine.registerFonts() }

    public var body: some View {
        GeometryReader { outer in
          let win = CineSafe.window
          let top = max(outer.safeAreaInsets.top, win.top + 44)
          let bottom = max(outer.safeAreaInsets.bottom, win.bottom)
          GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let progH: CGFloat = 40
            let nameH: CGFloat = 200
            let ctrlH: CGFloat = 60
            let avail = H - top - progH - nameH - ctrlH - bottom - 10
            let R = max(110, min(W * 0.46, avail / 2))
            let cy = top + progH + min(max((avail - 2 * R) * 0.45, 4), 50) + R
            ZStack(alignment: .top) {
                Color(red: 0.02, green: 0.016, blue: 0.05)
                CineBackground(scene: m.scene).id(m.scene.id).transition(.opacity).frame(width: W, height: H).clipped()
                LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .black.opacity(0.30), location: 0.16), .init(color: .black.opacity(0.22), location: 0.45),
                                       .init(color: .black.opacity(0.42), location: 0.62), .init(color: .black.opacity(0.74), location: 1)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                AsmaDialCanvas(m: m, R: R, cy: cy, progTop: top + 6)
                    .frame(width: W, height: H)
                    .contentShape(Rectangle())
                    .onTapGesture { m.next() }
                    .gesture(DragGesture(minimumDistance: 24).onEnded { v in
                        let dx = v.translation.width
                        guard abs(dx) > 48, abs(dx) > abs(v.translation.height) else { return }
                        dx > 0 ? m.next() : m.prev()      // right-to-left: swipe right = next
                    })
                HStack(spacing: 0) {
                    Text(verbatim: "\(m.done ? AsmaModel.count : m.idx + 1) / \(AsmaModel.count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(.white.opacity(0.86))
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(width: 64, alignment: .trailing)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 26)
                .frame(width: W, height: 24)
                .padding(.top, top - 2)
                .allowsHitTesting(false)
                ZStack {
                    if m.done { AsmaDoneBlock { m.next() }.transition(.opacity) }
                    else { AsmaNameBlock(n: AsmaData.names[m.idx]).id(m.idx).transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity)) }
                }
                .frame(width: W, height: nameH, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { m.next() }
                .padding(.top, cy + R + 18)
                VStack(spacing: 8) {
                    Spacer()
                    if m.idx == 0 && !m.done {
                        Text(verbatim: "اضغط للانتقال للاسم التالي").font(.custom("Tajawal-Medium", size: 12)).foregroundColor(.white.opacity(0.4))
                    }
                    HStack(spacing: 8) {
                        glass("chevron.right", enabled: m.idx > 0 || m.done) { m.prev() }
                        HStack(spacing: 10) {
                            pill("list.bullet", "كل الأسماء") { m.showList = true }
                            pill("photo.on.rectangle", "الخلفية") { m.showScenes = true }
                        }
                        .frame(maxWidth: .infinity)
                        glass("chevron.left", enabled: true) { m.next() }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, bottom + 14)
                .frame(width: W, height: H)
            }
            .frame(width: W, height: H)
          }
          .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .rightToLeft)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: "أسماء الله الحسنى").font(.custom("Tajawal-Bold", size: 17)).foregroundColor(.white)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { m.muted.toggle(); CineAudio.shared.muted = m.muted } label: {
                    Image(systemName: m.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                }
                .accessibilityLabel(Text(verbatim: m.muted ? "تشغيل الصوت" : "كتم الصوت"))
            }
        }
        .sheet(isPresented: $m.showScenes) {
            CineScenePicker(current: m.scene.id) { sc in
                withAnimation(.easeInOut(duration: 0.6)) { m.scene = sc }
                Cine.save(sc); CineAudio.shared.ambient(Cine.ambient(sc))
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $m.showList) {
            AsmaListSheet(current: m.done ? -1 : m.idx) { i in m.jump(i) }
                .presentationDetents([.large])
        }
        .onAppear {
            guard !m.started else { return }
            m.started = true
            CineAudio.shared.prepare()
            CineAudio.shared.ambient(Cine.ambient(m.scene))
            m.enter()
        }
        .onDisappear { CineAudio.shared.leave(); m.started = false }
    }

    private func pill(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(verbatim: title).font(.custom("Tajawal-Bold", size: 13)).lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func glass(_ icon: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(enabled ? 1 : 0.35))
                .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(enabled ? 0.11 : 0.05)))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

struct AsmaNameBlock: View {
    let n: AsmName
    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: n.name).font(.custom("Amiri-Regular", size: 46)).foregroundColor(.white.opacity(0.96)).lineLimit(1).minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.55), radius: 10, y: 3)
                .frame(height: 74)
            RoundedRectangle(cornerRadius: 2).fill(AsmaUI.red).frame(width: 30, height: 2.5).padding(.top, 2)
            Spacer().frame(height: 12)
            Text(verbatim: n.meaning).font(.custom("Tajawal-Medium", size: 16.5)).foregroundColor(.white.opacity(0.78))
                .multilineTextAlignment(.center).lineSpacing(5).lineLimit(3)
                .shadow(color: .black.opacity(0.5), radius: 5, y: 1)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity)
    }
}

struct AsmaDoneBlock: View {
    let restart: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "أتممت الأسماء الحسنى التسعة والتسعين").font(.custom("Tajawal-Bold", size: 18))
                .foregroundColor(.white).multilineTextAlignment(.center).lineLimit(2)
            Spacer().frame(height: 8)
            Text(verbatim: "«" + AsmaData.hadith + "»").font(.custom("Amiri-Regular", size: 16)).foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center).lineSpacing(5).lineLimit(3)
            Text(verbatim: AsmaData.hadithRef).font(.custom("Tajawal-Medium", size: 11.5)).foregroundColor(.white.opacity(0.48)).lineLimit(1)
            Spacer().frame(height: 10)
            Button(action: restart) {
                Text(verbatim: "ابدأ من جديد").font(.custom("Tajawal-Bold", size: 15)).foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 8).background(Capsule().fill(AsmaUI.red))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}

/// All 99 names in a list; tapping one moves the needle there.
struct AsmaListSheet: View {
    let current: Int
    let pick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 38, height: 5).padding(.top, 8)
                Text(verbatim: "أسماء الله الحسنى").font(.custom("Tajawal-Bold", size: 19)).foregroundColor(.white).padding(.bottom, 6)
                ForEach(AsmaData.names) { n in
                    let i = n.n - 1
                    Button { pick(i); dismiss() } label: {
                        HStack(spacing: 12) {
                            Text(verbatim: "\(n.n)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.55)).frame(width: 28)
                            Text(verbatim: n.name).font(.custom("Amiri-Regular", size: 22)).foregroundColor(.white)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.white.opacity(i == current ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(i == current ? AsmaUI.red.opacity(0.8) : .clear, lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .rightToLeft)
    }
}
