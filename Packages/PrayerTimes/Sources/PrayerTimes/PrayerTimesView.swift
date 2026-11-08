import SwiftUI
import CoreLocation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// One-shot GPS reader (permission asked only when the user taps «موقعي»).
final class PrLocator: NSObject, CLLocationManagerDelegate {
    private let lm = CLLocationManager()
    var onFix: ((CLLocation) -> Void)?
    var onFail: ((String) -> Void)?
    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    func request() {
        switch lm.authorizationStatus {
        case .notDetermined: lm.requestWhenInUseAuthorization()
        case .denied, .restricted: onFail?("الموقع مقفل من الإعدادات. اختر مدينتك من القائمة أو افتح إذن الموقع.")
        default: lm.requestLocation()
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s == .authorizedWhenInUse || s == .authorizedAlways { manager.requestLocation() }
        else if s == .denied { onFail?("ما وصلنا إذن الموقع. اختر مدينتك من القائمة.") }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let l = locations.last { onFix?(l) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onFail?("ما قدرنا نحدد موقعك الحين. جرّب مرة ثانية أو اختر مدينتك.")
    }
}

struct PrSlot: Identifiable {
    var id: Int { prayer.rawValue }
    let prayer: PrPrayer
    let time: Date
    let iqama: Date?
}

final class PrModel: ObservableObject {
    private let d = UserDefaults.standard
    private let k = "alsalmi.prayer."
    private let locator = PrLocator()

    @Published var methodId: String { didSet { save() } }
    @Published var hanafi: Bool { didSet { save() } }
    @Published var placeName: String
    @Published var lat: Double
    @Published var lng: Double
    @Published var tzId: String
    @Published var iqama: [Int] { didSet { save() } }   // fajr, dhuhr, asr, maghrib, isha
    @Published var notify: Set<Int> { didSet { save(); reschedule() } }
    @Published var showPlaces = false
    @Published var showSettings = false
    @Published var query = ""
    @Published var latText = ""
    @Published var lngText = ""
    @Published var locating = false
    @Published var message = ""

    static let iqamaDefaults = [25, 20, 20, 10, 20]

    init() {
        methodId = d.string(forKey: k + "method") ?? "umm"
        hanafi = d.bool(forKey: k + "hanafi")
        placeName = d.string(forKey: k + "place") ?? "الطائف"
        let la = d.object(forKey: k + "lat") as? Double
        lat = la ?? 21.2703
        lng = (d.object(forKey: k + "lng") as? Double) ?? 40.4158
        tzId = d.string(forKey: k + "tz") ?? "Asia/Riyadh"
        let iq = d.array(forKey: k + "iqama") as? [Int] ?? []
        iqama = iq.count == 5 ? iq : PrModel.iqamaDefaults
        notify = Set((d.array(forKey: k + "notify") as? [Int]) ?? [])
        locator.onFix = { [weak self] l in DispatchQueue.main.async { self?.useGPS(l) } }
        locator.onFail = { [weak self] t in DispatchQueue.main.async { self?.locating = false; self?.message = t } }
    }

    private func save() {
        d.set(methodId, forKey: k + "method"); d.set(hanafi, forKey: k + "hanafi")
        d.set(placeName, forKey: k + "place"); d.set(lat, forKey: k + "lat"); d.set(lng, forKey: k + "lng"); d.set(tzId, forKey: k + "tz")
        d.set(iqama, forKey: k + "iqama"); d.set(Array(notify), forKey: k + "notify")
    }

    var method: PrMethod { PrMethod.byId(methodId) }
    var zone: TimeZone { TimeZone(identifier: tzId) ?? .current }

    func choose(_ c: PrCity) {
        placeName = c.name; lat = c.lat; lng = c.lng; tzId = c.tz
        save(); reschedule(); showPlaces = false
    }
    func locate() { locating = true; message = ""; locator.request() }
    private func useGPS(_ l: CLLocation) {
        locating = false
        lat = l.coordinate.latitude; lng = l.coordinate.longitude; tzId = TimeZone.current.identifier
        // name it after the nearest city in the built-in list (offline)
        var best: (PrCity, Double)? = nil
        for c in PrCity.all {
            let dist = CLLocation(latitude: c.lat, longitude: c.lng).distance(from: l)
            if best == nil || dist < best!.1 { best = (c, dist) }
        }
        if let b = best, b.1 < 40_000 { placeName = b.0.name + " (موقعي)" } else { placeName = "موقعي الحالي" }
        save(); reschedule(); showPlaces = false
    }
    func applyManual() {
        let la = Double(latText.replacingOccurrences(of: ",", with: ".")) ?? .nan
        let lo = Double(lngText.replacingOccurrences(of: ",", with: ".")) ?? .nan
        guard la.isFinite, lo.isFinite, abs(la) <= 66, abs(lo) <= 180 else { message = "الإحداثيات غير صحيحة (خط العرض بين -66 و66)"; return }
        lat = la; lng = lo; tzId = TimeZone.current.identifier
        placeName = String(format: "%.3f، %.3f", la, lo)
        save(); reschedule(); showPlaces = false
    }

    func slots(for date: Date) -> [PrSlot] {
        let t = PrEngine.day(date, lat: lat, lng: lng, zone: zone, method: method, hanafi: hanafi)
        var out: [PrSlot] = []
        for p in PrPrayer.allCases {
            guard let at = t[p] else { continue }
            var iq: Date? = nil
            if let i = iqIndex(p) { iq = at.addingTimeInterval(Double(iqama[i]) * 60) }
            out.append(PrSlot(prayer: p, time: at, iqama: iq))
        }
        return out
    }
    func iqIndex(_ p: PrPrayer) -> Int? {
        switch p { case .fajr: return 0; case .dhuhr: return 1; case .asr: return 2; case .maghrib: return 3; case .isha: return 4; case .sunrise: return nil }
    }

    /// Previous and next prayer (sunrise counts as a time, not a prayer).
    func around(_ now: Date) -> (prev: PrSlot?, next: PrSlot?) {
        let day = 86400.0
        let all = (slots(for: now.addingTimeInterval(-day)) + slots(for: now) + slots(for: now.addingTimeInterval(day))).filter { $0.prayer.isPrayer }
        let prev = all.last { $0.time <= now }
        let next = all.first { $0.time > now }
        return (prev, next)
    }

    func toggleNotify(_ p: PrPrayer) {
        if notify.contains(p.rawValue) { notify.remove(p.rawValue); return }
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            DispatchQueue.main.async {
                if ok { self.notify.insert(p.rawValue) } else { self.message = "التنبيهات مقفلة من إعدادات الجهاز." }
            }
        }
        #endif
    }

    /// Local notifications for the next 7 days (no server).
    func reschedule() {
        #if canImport(UserNotifications)
        let c = UNUserNotificationCenter.current()
        let ids = (0..<7).flatMap { day in PrPrayer.allCases.map { "alsalmi.prayer.\(day).\($0.rawValue)" } }
        c.removePendingNotificationRequests(withIdentifiers: ids)
        guard !notify.isEmpty else { return }
        let now = Date()
        for day in 0..<7 {
            for s in slots(for: now.addingTimeInterval(Double(day) * 86400)) where notify.contains(s.prayer.rawValue) && s.time > now {
                let n = UNMutableNotificationContent()
                n.title = "حان وقت صلاة " + s.prayer.name
                n.body = placeName + " — " + PrFmt.time(s.time, zone)
                n.sound = .default
                var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: s.time)
                let req = UNNotificationRequest(identifier: "alsalmi.prayer.\(day).\(s.prayer.rawValue)", content: n,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                c.add(req)
            }
        }
        #endif
    }

    var filteredCities: [PrCity] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return PrCity.all }
        return PrCity.all.filter { $0.name.contains(q) || $0.region.contains(q) }
    }
}

enum PrFmt {
    static func time(_ d: Date, _ z: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = z
        f.dateFormat = "h:mm"
        let h = Calendar(identifier: .gregorian).dateComponents(in: z, from: d).hour ?? 0
        return f.string(from: d) + (h < 12 ? " ص" : " م")
    }
    static func span(_ s: TimeInterval, seconds: Bool) -> String {
        let t = max(0, Int(s))
        let h = t / 3600, m = (t % 3600) / 60, x = t % 60
        if seconds { return String(format: "%02d:%02d:%02d", h, m, x) }
        if h > 0 { return String(h) + " س " + String(m) + " د" }
        return String(m) + " دقيقة"
    }
    static func dates(_ d: Date, _ z: TimeZone) -> String {
        let g = DateFormatter()
        g.locale = Locale(identifier: "ar"); g.timeZone = z; g.calendar = Calendar(identifier: .gregorian)
        g.dateFormat = "EEEE d MMMM"
        let h = DateFormatter()
        var hc = Calendar(identifier: .islamicUmmAlQura); hc.timeZone = z
        h.locale = Locale(identifier: "ar"); h.timeZone = z; h.calendar = hc
        h.dateFormat = "d MMMM y"
        return western(g.string(from: d) + " · " + h.string(from: d) + " هـ")
    }
    static func western(_ s: String) -> String {
        let map: [Character: Character] = ["٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9"]
        return String(s.map { map[$0] ?? $0 })
    }
}

/// «مواقيت الصلاة» — the button's single entry view.
public struct PrayerTimesView: View {
    @StateObject private var m = PrModel()
    public init() {}

    public var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            content(ctx.date)
        }
        .background(PrTheme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "مواقيت الصلاة"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { m.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel(Text(verbatim: "الإعدادات"))
            }
        }
        .sheet(isPresented: $m.showPlaces) { NavigationStack { places }.prRTL() }
        .sheet(isPresented: $m.showSettings) { NavigationStack { settings }.prRTL() }
        .onAppear { m.reschedule() }
        .tint(PrTheme.accent)
        .prRTL()
    }

    private func content(_ now: Date) -> some View {
        let a = m.around(now)
        let today = m.slots(for: now)
        return ScrollView {
            VStack(spacing: 16) {
                hero(now, a.prev, a.next)
                placeBar
                if !m.message.isEmpty {
                    Text(verbatim: m.message).font(.footnote).foregroundColor(PrTheme.warn)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                }
                PrCard(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(today) { s in row(s, isNext: a.next?.prayer == s.prayer && Calendar.current.isDate(a.next!.time, inSameDayAs: s.time)) }
                    }
                }
                infoLine
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func hero(_ now: Date, _ prev: PrSlot?, _ next: PrSlot?) -> some View {
        let total = (next?.time.timeIntervalSince(prev?.time ?? now) ?? 1)
        let done = now.timeIntervalSince(prev?.time ?? now)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "الصلاة القادمة").font(.subheadline).foregroundColor(.white.opacity(0.85))
                    Text(verbatim: next?.prayer.name ?? "—").font(.system(size: 34, weight: .bold)).foregroundColor(.white)
                    Text(verbatim: next.map { PrFmt.time($0.time, m.zone) } ?? "").font(.headline).foregroundColor(.white.opacity(0.9))
                }
                Spacer()
                PrRing(progress: total > 0 ? done / total : 0, size: 92, line: 8) {
                    VStack(spacing: 2) {
                        Text(verbatim: "بعد").font(.caption2).foregroundColor(.white.opacity(0.85))
                        Text(verbatim: PrFmt.span(next?.time.timeIntervalSince(now) ?? 0, seconds: true))
                            .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(.white)
                    }
                }
            }
            HStack(spacing: 8) {
                PrIcon(kind: "clock", color: .white.opacity(0.9), size: 16)
                if let p = prev {
                    Text(verbatim: "السابقة: " + p.prayer.name + " — مضى " + PrFmt.span(now.timeIntervalSince(p.time), seconds: false))
                        .font(.footnote.weight(.medium)).foregroundColor(.white)
                }
                Spacer()
                if let n = next, let iq = n.iqama {
                    Text(verbatim: "الإقامة " + PrFmt.time(iq, m.zone)).font(.footnote.weight(.semibold)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
            }
            Text(verbatim: PrFmt.dates(now, m.zone)).font(.caption).foregroundColor(.white.opacity(0.85))
        }
        .padding(20)
        .background(ZStack {
            PrTheme.gradient
            Circle().fill(Color.white.opacity(0.10)).frame(width: 200, height: 200).offset(x: -130, y: -70)
            Circle().fill(Color.white.opacity(0.06)).frame(width: 140, height: 140).offset(x: 150, y: 70)
        })
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: PrTheme.accent.opacity(0.3), radius: 16, y: 8)
    }

    private var placeBar: some View {
        HStack(spacing: 10) {
            Button { m.showPlaces = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(verbatim: m.placeName).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.subheadline.weight(.semibold)).foregroundColor(PrTheme.accent)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(PrTheme.soft))
            }
            .buttonStyle(PrPress())
            Spacer()
            Button { m.locate() } label: {
                HStack(spacing: 6) {
                    if m.locating { ProgressView().scaleEffect(0.8) } else { Image(systemName: "location.fill") }
                    Text(verbatim: "موقعي")
                }
                .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(PrTheme.gradient))
            }
            .buttonStyle(PrPress())
        }
    }

    private func row(_ s: PrSlot, isNext: Bool) -> some View {
        let on = m.notify.contains(s.prayer.rawValue)
        return HStack(spacing: 12) {
            PrIcon(kind: s.prayer.glyph, color: isNext ? .white : PrTheme.accent, size: 22)
                .frame(width: 40, height: 40)
                .background(Circle().fill(isNext ? Color.white.opacity(0.2) : PrTheme.soft))
                .foregroundColor(isNext ? .white : PrTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: s.prayer.name).font(.headline)
                if let iq = s.iqama {
                    Text(verbatim: "الإقامة " + PrFmt.time(iq, m.zone)).font(.caption).foregroundColor(isNext ? .white.opacity(0.85) : .secondary)
                }
            }
            Spacer()
            Text(verbatim: PrFmt.time(s.time, m.zone)).font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
            if s.prayer.isPrayer {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { m.toggleNotify(s.prayer) } } label: {
                    Image(systemName: on ? "bell.fill" : "bell.slash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isNext ? .white : (on ? PrTheme.accent : .secondary))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PrPress())
                .accessibilityLabel(Text(verbatim: "تنبيه " + s.prayer.name))
            } else {
                Color.clear.frame(width: 34, height: 34)
            }
        }
        .foregroundColor(isNext ? .white : .primary)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isNext ? AnyShapeStyle(PrTheme.gradient) : AnyShapeStyle(Color.clear))
        )
        .animation(.easeInOut(duration: 0.4), value: isNext)
    }

    private var infoLine: some View {
        Text(verbatim: "طريقة الحساب: " + m.method.name + " · العصر: " + (m.hanafi ? "الحنفي" : "الجمهور (شافعي)") + "\nالأوقات محسوبة على جهازك بدون إنترنت.")
            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var places: some View {
        List {
            Section {
                PrSearch(placeholder: "ابحث عن مدينة أو دولة", text: $m.query)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                Button { m.locate() } label: {
                    Label { Text(verbatim: m.locating ? "جاري تحديد موقعك…" : "استخدم موقعي (GPS)") } icon: { Image(systemName: "location.fill") }
                }
            }
            let groups = ["السعودية", "اليمن", "الدول العربية", "العالم"]
            let xs = m.filteredCities
            if xs.isEmpty {
                Section { PrEmpty(icon: "mappin.slash", title: "ما لقينا المدينة", message: "اكتب الإحداثيات تحت، أو استخدم موقعك.") }
            }
            ForEach(groups, id: \.self) { g in
                let gx = xs.filter { $0.region == g }
                if !gx.isEmpty {
                    Section {
                        ForEach(gx) { c in
                            Button { m.choose(c) } label: {
                                HStack {
                                    Text(verbatim: c.name).foregroundColor(.primary)
                                    Spacer()
                                    if m.placeName == c.name { Image(systemName: "checkmark").foregroundColor(PrTheme.accent) }
                                }
                            }
                        }
                    } header: { Text(verbatim: g) }
                }
            }
            Section {
                TextField(text: $m.latText) { Text(verbatim: "خط العرض، مثل 21.27") }.keyboardType(.numbersAndPunctuation)
                TextField(text: $m.lngText) { Text(verbatim: "خط الطول، مثل 40.42") }.keyboardType(.numbersAndPunctuation)
                Button { m.applyManual() } label: { Text(verbatim: "اعتمد الإحداثيات") }
            } header: { Text(verbatim: "إحداثيات يدوية") } footer: { Text(verbatim: "تُحسب بتوقيت جهازك.") }
        }
        .navigationTitle(Text(verbatim: "المدينة"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button { m.showPlaces = false } label: { Text(verbatim: "تم") } } }
    }

    private var settings: some View {
        Form {
            Section {
                Picker(selection: $m.methodId) {
                    ForEach(PrMethod.all) { x in Text(verbatim: x.name).tag(x.id) }
                } label: { Text(verbatim: "طريقة الحساب") }
                Picker(selection: $m.hanafi) {
                    Text(verbatim: "الجمهور").tag(false)
                    Text(verbatim: "الحنفي").tag(true)
                } label: { Text(verbatim: "وقت العصر") }
                .pickerStyle(.segmented)
            } header: { Text(verbatim: "الحساب") } footer: { Text(verbatim: "أم القرى: الفجر 18.5°، والعشاء بعد المغرب بـ90 دقيقة (120 في رمضان).") }
            Section {
                ForEach(0..<5, id: \.self) { i in
                    Stepper(value: $m.iqama[i], in: 0...60) {
                        HStack {
                            Text(verbatim: ["الفجر", "الظهر", "العصر", "المغرب", "العشاء"][i])
                            Spacer()
                            Text(verbatim: String(m.iqama[i]) + " دقيقة").foregroundColor(.secondary).monospacedDigit()
                        }
                    }
                }
                Button { m.iqama = PrModel.iqamaDefaults } label: { Text(verbatim: "رجّع الافتراضي") }
            } header: { Text(verbatim: "الإقامة بعد الأذان") }
        }
        .navigationTitle(Text(verbatim: "الإعدادات"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button { m.showSettings = false; m.reschedule() } label: { Text(verbatim: "تم") } } }
    }
}
