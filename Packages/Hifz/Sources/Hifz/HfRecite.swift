import SwiftUI
import Speech
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// «تسميع» (added at his request, Nov 8 2026): the verses start hidden; he recites into the mic and each
/// correctly recited word appears in place. Matching uses a normalised copy of the words only;
/// the displayed Quran text is never changed.
enum HfMatch {
    /// For matching only: no tashkeel or Quranic marks, one alef, ة→ه, ى→ي, hamza seats unified, no tatweel.
    static func norm(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            let v = u.value
            if (0x064B...0x065F).contains(v) || v == 0x0670 || (0x0610...0x061A).contains(v) || (0x06D6...0x06ED).contains(v) || v == 0x0640 { continue }
            switch v {
            case 0x0622, 0x0623, 0x0625, 0x0671, 0x0672, 0x0673: out.append(Unicode.Scalar(0x0627)!)
            case 0x0629: out.append(Unicode.Scalar(0x0647)!)
            case 0x0649: out.append(Unicode.Scalar(0x064A)!)
            case 0x0624: out.append(Unicode.Scalar(0x0648)!)
            case 0x0626: out.append(Unicode.Scalar(0x064A)!)
            case 0x0621: continue
            default:
                if (0x0621...0x064A).contains(v) || (0x0671...0x06D3).contains(v) { out.append(u) }
            }
        }
        return String(out)
    }

    static func lev(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    /// The same word: exact after normalising, or one letter off for words of 4+ letters.
    static func same(_ heard: String, _ expected: String) -> Bool {
        if heard == expected { return true }
        let a = Array(heard), b = Array(expected)
        guard b.count >= 4 else { return false }
        return lev(a, b) <= 1
    }
}

final class HfReciter: ObservableObject {
    struct Word { let ayah: Int; let index: Int; let norm: String }

    @Published private(set) var expected: [Word] = []
    /// how many expected words were recited correctly (in order)
    @Published private(set) var pos = 0
    /// the expected word that was missed or said wrong (highlighted until it is said)
    @Published private(set) var wrongAt: Int? = nil
    @Published private(set) var listening = false
    @Published var message = ""
    @Published var denied = false

    private var base = 0
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    private var rangeKey = ""
    private var startedAt = Date()
    /// which recognition task is current; callbacks of older tasks are ignored
    private var gen = 0
    private var quickFails = 0

    /// Build the expected words for a range (each ayah's own words, in order). Keeps progress if the range is the same.
    func load(surah: Int, ayahs: [Int], words: (Int) -> [String]) {
        let key = String(surah) + ":" + ayahs.map(String.init).joined(separator: ",")
        if key == rangeKey { return }
        stop()
        rangeKey = key
        var xs: [Word] = []
        for a in ayahs {
            for (i, w) in words(a).enumerated() {
                let n = HfMatch.norm(w)
                if !n.isEmpty { xs.append(Word(ayah: a, index: i, norm: n)) }
            }
        }
        expected = xs; pos = 0; base = 0; wrongAt = nil; message = ""
    }

    /// How many words of this ayah are revealed, and which of its words is marked wrong.
    func revealed(ayah: Int) -> Set<Int> {
        Set(expected.prefix(pos).filter { $0.ayah == ayah }.map { $0.index })
    }
    func wrongIndex(ayah: Int) -> Int? {
        guard let w = wrongAt, w < expected.count, expected[w].ayah == ayah else { return nil }
        return expected[w].index
    }
    var done: Bool { !expected.isEmpty && pos >= expected.count }

    func reset() {
        stop()
        pos = 0; base = 0; wrongAt = nil; message = ""
    }

    func toggle() { listening ? stop() : start() }

    func start() {
        message = ""
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async {
                guard st == .authorized else { self.refuse(); return }
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    DispatchQueue.main.async { ok ? self.begin() : self.refuse() }
                }
            }
        }
    }

    private func refuse() {
        denied = true
        listening = false
        message = "التسميع يحتاج إذن المايك والتعرّف على الكلام. فعّلهم من الإعدادات ▸ مركز الصديق."
    }

    private func begin() {
        guard let rec = recognizer, rec.isAvailable else {
            message = "التعرّف على الكلام بالعربي مو متاح على هذا الجهاز الحين."
            return
        }
        denied = false
        do {
            if !engine.isRunning {
                let s = AVAudioSession.sharedInstance()
                try s.setCategory(.record, mode: .measurement, options: .duckOthers)
                try s.setActive(true, options: .notifyOthersOnDeactivation)
                let input = engine.inputNode
                input.removeTap(onBus: 0)
                // the mic stays open for the whole «تسميع»; each buffer goes to the CURRENT recognition request
                input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buf, _ in
                    self?.request?.append(buf)
                }
                engine.prepare()
                try engine.start()
            }
            listening = true
            quickFails = 0
            newRecognition(rec)
        } catch {
            message = "ما قدرت أشغّل المايك."
            endSession()
            listening = false
        }
    }

    /// One recognition task. iOS ends a task on a pause, on its time limit or with an error; while «تسميع» is on
    /// (until he taps stop or the passage is done) a new task starts at once on the same open mic.
    private func newRecognition(_ rec: SFSpeechRecognizer) {
        gen += 1
        let g = gen
        request?.endAudio()
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        base = pos
        startedAt = Date()
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                // a task we already replaced or stopped (its cancel also lands here): ignore it
                guard let self = self, g == self.gen else { return }
                if let r = result {
                    self.heard(r.bestTranscription.formattedString)
                    if !r.bestTranscription.formattedString.isEmpty { self.quickFails = 0 }
                }
                guard error != nil || (result?.isFinal ?? false) else { return }
                guard self.listening, !self.done else { return }
                // only a mic that gives nothing at all, task after task, ends it on its own
                let quick = error != nil && Date().timeIntervalSince(self.startedAt) < 1.0
                self.quickFails = quick ? self.quickFails + 1 : 0
                if self.quickFails >= 8 {
                    self.stop()
                    self.message = "ما وصلني صوت من المايك. جرّب مرة ثانية."
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + (quick ? 0.4 : 0.05)) {
                    guard g == self.gen, self.listening, !self.done, let rec = self.recognizer else { return }
                    self.newRecognition(rec)
                }
            }
        }
    }

    private func endSession() {
        gen += 1   // any callback still in flight belongs to an ended task
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        base = pos
    }

    func stop() {
        listening = false
        endSession()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Walk the expected words in order against what was heard in this session (partial results are re-read whole).
    func heard(_ transcript: String) {
        let t = transcript.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { HfMatch.norm(String($0)) }.filter { !$0.isEmpty }
        var p = base
        var wrong: Int? = nil
        var i = 0
        while i < t.count && p < expected.count {
            let e = expected[p].norm
            if HfMatch.same(t[i], e) {
                p += 1; i += 1; wrong = nil
            } else if i + 1 < t.count && HfMatch.same(t[i] + t[i + 1], e) {
                p += 1; i += 2; wrong = nil   // e.g. «يا أيها» heard as two words, written as one
            } else {
                wrong = p; i += 1
            }
        }
        let gained = p > pos
        if p != pos { withAnimation(.easeOut(duration: 0.25)) { pos = p } }
        wrongAt = wrong
        #if canImport(UIKit)
        if gained { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        #endif
        if done { stop(); message = "ما شاء الله، سمّعت المقطع كامل ✓" }
    }

    #if DEBUG
    /// CI screenshots only (the simulator has no real recitation): reveal n words and mark the next one wrong.
    func demo(_ n: Int) {
        pos = min(n, expected.count)
        wrongAt = pos < expected.count ? pos : nil
    }
    #endif
}

/// Eastern Arabic digits for the progress line (e.g. ٥/١٢).
enum HfDigits {
    static func ar(_ n: Int) -> String {
        let d: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
        return String(String(n).map { c in c.wholeNumberValue.map { d[$0] } ?? c })
    }
}

/// The mic panel shown above the verses in «تسميع».
struct HfRecitePanel: View {
    @ObservedObject var r: HfReciter
    var body: some View {
        HfCard {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Button { r.toggle() } label: {
                        ZStack {
                            Circle().fill(HfTheme.gradient).frame(width: 64, height: 64)
                                .shadow(color: HfTheme.accent.opacity(0.35), radius: r.listening ? 14 : 6, y: 4)
                            if r.listening {
                                Circle().stroke(HfTheme.accent.opacity(0.35), lineWidth: 3).frame(width: 78, height: 78)
                            }
                            Image(systemName: r.listening ? "stop.fill" : "mic.fill").font(.system(size: 26, weight: .semibold)).foregroundColor(.white)
                        }
                        .frame(width: 80, height: 80)
                    }
                    .buttonStyle(HfPress())
                    .accessibilityLabel(Text(verbatim: r.listening ? "إيقاف" : "ابدأ التسميع"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: r.listening ? "أسمعك… اقرأ" : (r.done ? "خلصت المقطع" : "اضغط المايك واقرأ من حفظك")).font(.headline)
                        Text(verbatim: HfDigits.ar(r.pos) + "/" + HfDigits.ar(r.expected.count) + " كلمة")
                            .font(.subheadline.weight(.semibold)).foregroundColor(HfTheme.accent)
                        if r.wrongAt != nil {
                            Text(verbatim: "الكلمة المعلّمة ما انسمعت صح، أعدها").font(.caption).foregroundColor(HfTheme.warn)
                        }
                    }
                    Spacer(minLength: 0)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(HfTheme.soft)
                        Capsule().fill(HfTheme.gradient).frame(width: g.size.width * CGFloat(r.pos) / CGFloat(max(1, r.expected.count)))
                    }
                }
                .frame(height: 7)
                if !r.message.isEmpty {
                    Text(verbatim: r.message).font(.footnote).foregroundColor(r.done ? HfTheme.good : HfTheme.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    if r.denied {
                        Button {
                            #if canImport(UIKit)
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                            #endif
                        } label: {
                            Label { Text(verbatim: "افتح الإعدادات") } icon: { Image(systemName: "gearshape") }
                                .font(.caption.weight(.semibold)).foregroundColor(HfTheme.accent)
                                .padding(.horizontal, 10).padding(.vertical, 7).background(Capsule().fill(HfTheme.soft))
                        }
                        .buttonStyle(HfPress())
                    }
                    Spacer()
                    Button { withAnimation { r.reset() } } label: {
                        Label { Text(verbatim: "من جديد") } icon: { Image(systemName: "arrow.counterclockwise") }
                            .font(.caption.weight(.semibold)).foregroundColor(HfTheme.accent)
                            .padding(.horizontal, 10).padding(.vertical, 7).background(Capsule().fill(HfTheme.soft))
                    }
                    .buttonStyle(HfPress())
                }
            }
        }
    }
}
