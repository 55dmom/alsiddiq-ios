import SwiftUI
import UIKit
import AVFoundation
import CoreText

/// One bundled background: a looping 540p video, its poster and its ambient sound (all inside this package, offline).
struct CineScene: Identifiable, Equatable {
    let id: String
    let name: String
}

enum Cine {
    static let scenes: [CineScene] = [
        CineScene(id: "storm_sea", name: "بحر وبرق"),
        CineScene(id: "moon_sea", name: "قمر على البحر"),
        CineScene(id: "desert_night", name: "ليل الصحراء"),
        CineScene(id: "misty_mountains", name: "جبال وضباب"),
    ]
    static func url(_ name: String, _ ext: String) -> URL? { Bundle.module.url(forResource: name, withExtension: ext) }
    static func video(_ s: CineScene) -> URL? { url("bg_" + s.id, "mp4") }
    static func poster(_ s: CineScene) -> UIImage? { url("poster_" + s.id, "jpg").flatMap { UIImage(contentsOfFile: $0.path) } }
    static func ambient(_ s: CineScene) -> URL? { url("amb_" + s.id, "m4a") }

    private static let fontsOnce: Void = {
        for f in ["Amiri-Regular", "Tajawal-Bold", "Tajawal-Medium"] {
            if let u = url(f, "ttf") { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
        }
    }()
    /// Registers the bundled Amiri + Tajawal fonts for this process (once).
    static func registerFonts() { _ = fontsOnce }

    static let warm = Color(red: 0.98, green: 0.62, blue: 0.32)

    /// Western digits (the app's choice); Arabic-Indic would be String(n) with an ar locale formatter.
    static func num(_ n: Int) -> String { String(n) }

    static let sceneKey = "alsalmi.asma.scene"
    /// Each opening shows the NEXT scene (video + its own ambient sound) after the last one, and remembers it.
    static func savedScene() -> CineScene {
        let id = UserDefaults.standard.string(forKey: sceneKey) ?? ""
        let next: CineScene
        if let i = scenes.firstIndex(where: { $0.id == id }) { next = scenes[(i + 1) % scenes.count] } else { next = scenes[0] }
        save(next)
        return next
    }
    static func save(_ s: CineScene) { UserDefaults.standard.set(s.id, forKey: sceneKey) }
}

/// Glass ticks (3 variants, 6 players so fast taps overlap), a soft cue at the end of a round, and the scene's ambient loop.
final class CineAudio {
    static let shared = CineAudio()
    private let mk = "alsalmi.asma.muted"
    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: mk) }
        set { UserDefaults.standard.set(newValue, forKey: mk); newValue ? pauseAmbient() : resumeAmbient() }
    }
    private var taps: [AVAudioPlayer] = []
    private var tapIdx = 0
    private var amb: AVAudioPlayer?
    private var ambURL: URL?
    private var active = false

    func prepare() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if taps.isEmpty {
            let urls = ["tick1", "tick2", "tick3"].compactMap { Cine.url($0, "wav") }
            if !urls.isEmpty {
                taps = (0..<6).compactMap { i in
                    let p = try? AVAudioPlayer(contentsOf: urls[i % urls.count]); p?.enableRate = true; p?.prepareToPlay(); return p
                }
            }
        }
        // cue.m4a is a tonal chime: not played (no melodic sounds; the end of a round is the haptic only)
    }
    func tap() {
        guard !muted, !taps.isEmpty else { return }
        let p = taps[tapIdx % taps.count]; tapIdx += 1
        p.currentTime = 0; p.volume = 0.7; p.rate = Float.random(in: 0.96...1.04); p.play()
    }
    func complete() { }
    func ambient(_ url: URL?) {
        active = true
        if url == ambURL, amb != nil { if !muted { amb?.play() }; return }
        amb?.stop(); amb = nil; ambURL = url
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1; p.volume = 0
        amb = p
        if !muted { p.play(); p.setVolume(0.26, fadeDuration: 1.2) }
    }
    func pauseAmbient() { amb?.pause() }
    func resumeAmbient() { guard active, !muted, let p = amb else { return }; p.play(); p.setVolume(0.26, fadeDuration: 0.8) }
    func leave() { active = false; amb?.stop(); amb = nil; ambURL = nil }
}

/// Looping, muted, aspect-fill video; pauses in the background.
final class CinePlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var obs: [NSObjectProtocol] = []
    private var ready: NSKeyValueObservation?
    var onReady: (() -> Void)?

    func load(_ url: URL) {
        let item = AVPlayerItem(url: url)
        let p = AVQueuePlayer()
        p.isMuted = true
        p.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: p, templateItem: item)
        playerLayer.player = p
        playerLayer.videoGravity = .resizeAspectFill
        player = p
        p.play()
        ready = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] l, _ in
            if l.isReadyForDisplay { DispatchQueue.main.async { self?.onReady?(); self?.onReady = nil } }
        }
        let nc = NotificationCenter.default
        obs.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player?.pause(); CineAudio.shared.pauseAmbient()
        })
        obs.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player?.play(); CineAudio.shared.resumeAmbient()
        })
    }
    func stop() {
        ready?.invalidate(); ready = nil
        player?.pause()
        looper?.disableLooping(); looper = nil
        playerLayer.player = nil
        player = nil
        obs.forEach { NotificationCenter.default.removeObserver($0) }; obs = []
    }
    deinit { stop() }
}

struct CineVideo: UIViewRepresentable {
    let url: URL
    var onReady: () -> Void
    func makeUIView(context: Context) -> CinePlayerView {
        let v = CinePlayerView(); v.backgroundColor = .clear; v.isUserInteractionEnabled = false; v.onReady = onReady; v.load(url); return v
    }
    func updateUIView(_ v: CinePlayerView, context: Context) {}
    static func dismantleUIView(_ v: CinePlayerView, coordinator: ()) { v.stop() }
}

final class CineFlag: ObservableObject { @Published var on = false }

/// Poster first, then the looping video fades in over it.
struct CineBackground: View {
    let scene: CineScene
    @StateObject private var ready = CineFlag()
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.016, blue: 0.05)
            if let img = Cine.poster(scene) {
                Image(uiImage: img).resizable().scaledToFill()
            }
            if let u = Cine.video(scene) {
                CineVideo(url: u) { withAnimation(.easeOut(duration: 0.7)) { ready.on = true } }
                    .opacity(ready.on ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Round dots of light drifting up in the lower part of the screen.
enum CineParticles {
    static func rnd(_ i: Int, _ salt: Int) -> Double {
        var x = UInt64(i &* 2654435761 &+ salt &* 40503) ^ 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9; x = (x ^ (x >> 27)) &* 0x94D049BB133111EB; x ^= x >> 31
        return Double(x % 10_000) / 10_000
    }
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, count: Int = 28) {
        let w = size.width, h = size.height
        for i in 0..<count {
            let s1 = rnd(i, 1), s2 = rnd(i, 2), s3 = rnd(i, 3)
            let speed = 5 + 9 * s2
            let span = Double(h) * 0.62
            let m = (s1 * span + t * speed).truncatingRemainder(dividingBy: span)
            let yy = Double(h) - (Double(h) * 0.04 + m)
            let xx = Double(w) * s3 + sin(t * (0.3 + s1 * 0.4) + Double(i)) * 14
            let fade = sin(.pi * (m / span))
            let tw = 0.55 + 0.45 * sin(t * (1.2 + s2 * 1.6) + Double(i) * 1.7)
            let r = 0.8 + 1.5 * s2
            let a = 0.55 * fade * tw
            let p = CGPoint(x: xx, y: yy)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.85, green: 0.95, blue: 1).opacity(a * 0.35), .clear]), center: p, startRadius: 0, endRadius: r * 3))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Color(red: 0.92, green: 0.97, blue: 1).opacity(a)))
        }
    }
}

/// Dark scrim so the text reads over any scene (light in the middle, where the beads / dial sit).
struct CineScrim: View {
    var body: some View {
        LinearGradient(stops: [.init(color: .black.opacity(0.50), location: 0), .init(color: .black.opacity(0.18), location: 0.30),
                               .init(color: .black.opacity(0.0), location: 0.46), .init(color: .black.opacity(0.10), location: 0.70),
                               .init(color: .black.opacity(0.58), location: 1)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Scene picker: the 4 bundled backgrounds as tall cards.
struct CineScenePicker: View {
    let current: String
    let pick: (CineScene) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 38, height: 5).padding(.top, 8)
            Text(verbatim: "الخلفية").font(.system(size: 19, weight: .bold)).foregroundColor(.white)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Cine.scenes) { s in
                    Button { pick(s); dismiss() } label: {
                        ZStack(alignment: .bottom) {
                            if let img = Cine.poster(s) {
                                Image(uiImage: img).resizable().scaledToFill().frame(height: 200).clipped()
                            } else { Color.black.frame(height: 200) }
                            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                            Text(verbatim: s.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.white).padding(.bottom, 10)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(s.id == current ? Cine.warm : Color.white.opacity(0.12), lineWidth: s.id == current ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}

/// Reads the window's safe-area insets (status bar / home indicator) for layout under ignoresSafeArea().
enum CineSafe {
    static var window: UIEdgeInsets {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }
        return w?.safeAreaInsets ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
    }
}
