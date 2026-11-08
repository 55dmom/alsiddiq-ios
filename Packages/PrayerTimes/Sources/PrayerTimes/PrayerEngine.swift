import Foundation

/// Offline prayer-time engine (solar position after Meeus / praytimes.org), no network.
struct PrMethod: Identifiable, Equatable {
    let id: String
    let name: String
    let fajr: Double
    /// Isha as a sun angle, or nil when Isha is minutes after Maghrib.
    let isha: Double?
    let ishaMinutes: Double
    static let all: [PrMethod] = [
        PrMethod(id: "umm", name: "أم القرى (مكة)", fajr: 18.5, isha: nil, ishaMinutes: 90.0),
        PrMethod(id: "mwl", name: "رابطة العالم الإسلامي", fajr: 18.0, isha: 17.0, ishaMinutes: 0.0),
        PrMethod(id: "egypt", name: "الهيئة المصرية العامة للمساحة", fajr: 19.5, isha: 17.5, ishaMinutes: 0.0),
        PrMethod(id: "karachi", name: "جامعة العلوم الإسلامية بكراتشي", fajr: 18.0, isha: 18.0, ishaMinutes: 0.0),
        PrMethod(id: "isna", name: "أمريكا الشمالية (ISNA)", fajr: 15.0, isha: 15.0, ishaMinutes: 0.0),
        PrMethod(id: "kuwait", name: "الكويت", fajr: 18.0, isha: 17.5, ishaMinutes: 0.0),
        PrMethod(id: "qatar", name: "قطر", fajr: 18.0, isha: nil, ishaMinutes: 90.0),
        PrMethod(id: "dubai", name: "دبي", fajr: 18.2, isha: 18.2, ishaMinutes: 0.0),
    ]
    static func byId(_ id: String) -> PrMethod { all.first { $0.id == id } ?? all[0] }
}

struct PrCity: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let lat: Double
    let lng: Double
    let tz: String
    let region: String
    static let all: [PrCity] = [
        PrCity(name: "الطائف", lat: 21.2703, lng: 40.4158, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "مكة المكرمة", lat: 21.4225, lng: 39.8262, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "المدينة المنورة", lat: 24.4672, lng: 39.6111, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الرياض", lat: 24.7136, lng: 46.6753, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "جدة", lat: 21.4858, lng: 39.1925, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الدمام", lat: 26.4207, lng: 50.0888, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الخبر", lat: 26.2172, lng: 50.1971, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الظهران", lat: 26.2361, lng: 50.0393, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الجبيل", lat: 27.0046, lng: 49.646, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "القطيف", lat: 26.5196, lng: 50.0115, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الأحساء (الهفوف)", lat: 25.3833, lng: 49.5833, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "حفر الباطن", lat: 28.4328, lng: 45.9708, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "أبها", lat: 18.2164, lng: 42.5053, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "خميس مشيط", lat: 18.3, lng: 42.7333, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "بيشة", lat: 20.0005, lng: 42.6052, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "النماص", lat: 19.1167, lng: 42.1333, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "محايل عسير", lat: 18.55, lng: 42.05, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الباحة", lat: 20.0129, lng: 41.4677, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "بلجرشي", lat: 19.859, lng: 41.559, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "تبوك", lat: 28.3838, lng: 36.555, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "ضباء", lat: 27.351, lng: 35.69, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الوجه", lat: 26.2333, lng: 36.4667, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "أملج", lat: 25.0213, lng: 37.2685, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "بريدة", lat: 26.3592, lng: 43.9818, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "عنيزة", lat: 26.0843, lng: 43.9935, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الرس", lat: 25.8694, lng: 43.4973, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "حائل", lat: 27.5114, lng: 41.7208, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "جازان", lat: 16.8892, lng: 42.5511, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "صبيا", lat: 17.1495, lng: 42.6254, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "أبو عريش", lat: 16.9689, lng: 42.8325, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "صامطة", lat: 16.596, lng: 42.944, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "نجران", lat: 17.5656, lng: 44.2289, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "شرورة", lat: 17.4667, lng: 47.1167, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "ينبع", lat: 24.0895, lng: 38.0618, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "العلا", lat: 26.6084, lng: 37.923, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "رابغ", lat: 22.7986, lng: 39.0349, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الليث", lat: 20.15, lng: 40.2667, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "القنفذة", lat: 19.1264, lng: 41.0789, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "عرعر", lat: 30.9753, lng: 41.0381, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "سكاكا", lat: 29.9697, lng: 40.2064, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "القريات", lat: 31.3318, lng: 37.3428, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "طريف", lat: 31.6725, lng: 38.6637, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الخرج", lat: 24.1556, lng: 47.312, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الدوادمي", lat: 24.5077, lng: 44.3924, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "المجمعة", lat: 25.9039, lng: 45.3456, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الزلفي", lat: 26.2994, lng: 44.8154, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "وادي الدواسر", lat: 20.4667, lng: 44.7833, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "تربة", lat: 21.2142, lng: 41.6331, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "رنية", lat: 21.2667, lng: 42.85, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "الخرمة", lat: 21.9167, lng: 42.05, tz: "Asia/Riyadh", region: "السعودية"),
        PrCity(name: "صنعاء", lat: 15.3694, lng: 44.191, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "عدن", lat: 12.7855, lng: 45.0187, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "تعز", lat: 13.5795, lng: 44.0209, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "الحديدة", lat: 14.7978, lng: 42.9545, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "المكلا", lat: 14.5425, lng: 49.1242, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "سيئون", lat: 15.9431, lng: 48.7879, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "تريم", lat: 16.054, lng: 49.0, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "إب", lat: 13.9667, lng: 44.1833, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "ذمار", lat: 14.5427, lng: 44.4051, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "مأرب", lat: 15.4626, lng: 45.3256, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "صعدة", lat: 16.9402, lng: 43.7639, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "حجة", lat: 15.6943, lng: 43.6058, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "عمران", lat: 15.6594, lng: 43.9439, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "البيضاء", lat: 13.985, lng: 45.573, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "عتق", lat: 14.5377, lng: 46.8319, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "الغيضة", lat: 16.2079, lng: 52.176, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "لحج (الحوطة)", lat: 13.0583, lng: 44.8838, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "زنجبار", lat: 13.1287, lng: 45.3803, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "الضالع", lat: 13.6957, lng: 44.7314, tz: "Asia/Aden", region: "اليمن"),
        PrCity(name: "الكويت", lat: 29.3759, lng: 47.9774, tz: "Asia/Kuwait", region: "الدول العربية"),
        PrCity(name: "الدوحة", lat: 25.2854, lng: 51.531, tz: "Asia/Qatar", region: "الدول العربية"),
        PrCity(name: "المنامة", lat: 26.2285, lng: 50.586, tz: "Asia/Bahrain", region: "الدول العربية"),
        PrCity(name: "أبوظبي", lat: 24.4539, lng: 54.3773, tz: "Asia/Dubai", region: "الدول العربية"),
        PrCity(name: "دبي", lat: 25.2048, lng: 55.2708, tz: "Asia/Dubai", region: "الدول العربية"),
        PrCity(name: "الشارقة", lat: 25.3463, lng: 55.4209, tz: "Asia/Dubai", region: "الدول العربية"),
        PrCity(name: "مسقط", lat: 23.588, lng: 58.3829, tz: "Asia/Muscat", region: "الدول العربية"),
        PrCity(name: "صلالة", lat: 17.0151, lng: 54.0924, tz: "Asia/Muscat", region: "الدول العربية"),
        PrCity(name: "بغداد", lat: 33.3152, lng: 44.3661, tz: "Asia/Baghdad", region: "الدول العربية"),
        PrCity(name: "البصرة", lat: 30.5085, lng: 47.7804, tz: "Asia/Baghdad", region: "الدول العربية"),
        PrCity(name: "دمشق", lat: 33.5138, lng: 36.2765, tz: "Asia/Damascus", region: "الدول العربية"),
        PrCity(name: "بيروت", lat: 33.8938, lng: 35.5018, tz: "Asia/Beirut", region: "الدول العربية"),
        PrCity(name: "عمّان", lat: 31.9454, lng: 35.9284, tz: "Asia/Amman", region: "الدول العربية"),
        PrCity(name: "القدس", lat: 31.7683, lng: 35.2137, tz: "Asia/Jerusalem", region: "الدول العربية"),
        PrCity(name: "غزة", lat: 31.5017, lng: 34.4668, tz: "Asia/Gaza", region: "الدول العربية"),
        PrCity(name: "القاهرة", lat: 30.0444, lng: 31.2357, tz: "Africa/Cairo", region: "الدول العربية"),
        PrCity(name: "الإسكندرية", lat: 31.2001, lng: 29.9187, tz: "Africa/Cairo", region: "الدول العربية"),
        PrCity(name: "الخرطوم", lat: 15.5007, lng: 32.5599, tz: "Africa/Khartoum", region: "الدول العربية"),
        PrCity(name: "طرابلس", lat: 32.8872, lng: 13.1913, tz: "Africa/Tripoli", region: "الدول العربية"),
        PrCity(name: "تونس", lat: 36.8065, lng: 10.1815, tz: "Africa/Tunis", region: "الدول العربية"),
        PrCity(name: "الجزائر", lat: 36.7538, lng: 3.0588, tz: "Africa/Algiers", region: "الدول العربية"),
        PrCity(name: "الرباط", lat: 34.0209, lng: -6.8416, tz: "Africa/Casablanca", region: "الدول العربية"),
        PrCity(name: "الدار البيضاء", lat: 33.5731, lng: -7.5898, tz: "Africa/Casablanca", region: "الدول العربية"),
        PrCity(name: "نواكشوط", lat: 18.0735, lng: -15.9582, tz: "Africa/Nouakchott", region: "الدول العربية"),
        PrCity(name: "مقديشو", lat: 2.0469, lng: 45.3182, tz: "Africa/Mogadishu", region: "الدول العربية"),
        PrCity(name: "جيبوتي", lat: 11.5721, lng: 43.1456, tz: "Africa/Djibouti", region: "الدول العربية"),
        PrCity(name: "إسطنبول", lat: 41.0082, lng: 28.9784, tz: "Europe/Istanbul", region: "العالم"),
        PrCity(name: "أنقرة", lat: 39.9334, lng: 32.8597, tz: "Europe/Istanbul", region: "العالم"),
        PrCity(name: "طهران", lat: 35.6892, lng: 51.389, tz: "Asia/Tehran", region: "العالم"),
        PrCity(name: "إسلام آباد", lat: 33.6844, lng: 73.0479, tz: "Asia/Karachi", region: "العالم"),
        PrCity(name: "كراتشي", lat: 24.8607, lng: 67.0011, tz: "Asia/Karachi", region: "العالم"),
        PrCity(name: "نيودلهي", lat: 28.6139, lng: 77.209, tz: "Asia/Kolkata", region: "العالم"),
        PrCity(name: "دكا", lat: 23.8103, lng: 90.4125, tz: "Asia/Dhaka", region: "العالم"),
        PrCity(name: "جاكرتا", lat: -6.2088, lng: 106.8456, tz: "Asia/Jakarta", region: "العالم"),
        PrCity(name: "كوالالمبور", lat: 3.139, lng: 101.6869, tz: "Asia/Kuala_Lumpur", region: "العالم"),
        PrCity(name: "سنغافورة", lat: 1.3521, lng: 103.8198, tz: "Asia/Singapore", region: "العالم"),
        PrCity(name: "بكين", lat: 39.9042, lng: 116.4074, tz: "Asia/Shanghai", region: "العالم"),
        PrCity(name: "طوكيو", lat: 35.6762, lng: 139.6503, tz: "Asia/Tokyo", region: "العالم"),
        PrCity(name: "موسكو", lat: 55.7558, lng: 37.6173, tz: "Europe/Moscow", region: "العالم"),
        PrCity(name: "لندن", lat: 51.5074, lng: -0.1278, tz: "Europe/London", region: "العالم"),
        PrCity(name: "باريس", lat: 48.8566, lng: 2.3522, tz: "Europe/Paris", region: "العالم"),
        PrCity(name: "برلين", lat: 52.52, lng: 13.405, tz: "Europe/Berlin", region: "العالم"),
        PrCity(name: "مدريد", lat: 40.4168, lng: -3.7038, tz: "Europe/Madrid", region: "العالم"),
        PrCity(name: "روما", lat: 41.9028, lng: 12.4964, tz: "Europe/Rome", region: "العالم"),
        PrCity(name: "أمستردام", lat: 52.3676, lng: 4.9041, tz: "Europe/Amsterdam", region: "العالم"),
        PrCity(name: "بروكسل", lat: 50.8503, lng: 4.3517, tz: "Europe/Brussels", region: "العالم"),
        PrCity(name: "ستوكهولم", lat: 59.3293, lng: 18.0686, tz: "Europe/Stockholm", region: "العالم"),
        PrCity(name: "نيويورك", lat: 40.7128, lng: -74.006, tz: "America/New_York", region: "العالم"),
        PrCity(name: "واشنطن", lat: 38.9072, lng: -77.0369, tz: "America/New_York", region: "العالم"),
        PrCity(name: "تورنتو", lat: 43.6532, lng: -79.3832, tz: "America/Toronto", region: "العالم"),
        PrCity(name: "لوس أنجلوس", lat: 34.0522, lng: -118.2437, tz: "America/Los_Angeles", region: "العالم"),
        PrCity(name: "سيدني", lat: -33.8688, lng: 151.2093, tz: "Australia/Sydney", region: "العالم"),
        PrCity(name: "نيروبي", lat: -1.2921, lng: 36.8219, tz: "Africa/Nairobi", region: "العالم"),
        PrCity(name: "لاغوس", lat: 6.5244, lng: 3.3792, tz: "Africa/Lagos", region: "العالم"),
        PrCity(name: "أديس أبابا", lat: 9.03, lng: 38.74, tz: "Africa/Addis_Ababa", region: "العالم"),
        PrCity(name: "باكو", lat: 40.4093, lng: 49.8671, tz: "Asia/Baku", region: "العالم"),
        PrCity(name: "طشقند", lat: 41.2995, lng: 69.2401, tz: "Asia/Tashkent", region: "العالم"),
    ]
}

enum PrPrayer: Int, CaseIterable, Identifiable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha
    var id: Int { rawValue }
    var name: String {
        switch self {
        case .fajr: return "الفجر"
        case .sunrise: return "الشروق"
        case .dhuhr: return "الظهر"
        case .asr: return "العصر"
        case .maghrib: return "المغرب"
        case .isha: return "العشاء"
        }
    }
    var glyph: String {
        switch self {
        case .fajr, .isha: return "moon"
        case .sunrise, .maghrib: return "sunrise"
        case .dhuhr, .asr: return "sun"
        }
    }
    var isPrayer: Bool { self != .sunrise }
}

enum PrEngine {
    private static func r(_ d: Double) -> Double { d * .pi / 180 }
    private static func g(_ x: Double) -> Double { x * 180 / .pi }
    private static func fixA(_ a: Double) -> Double { let v = a.truncatingRemainder(dividingBy: 360); return v < 0 ? v + 360 : v }
    private static func fixH(_ h: Double) -> Double { let v = h.truncatingRemainder(dividingBy: 24); return v < 0 ? v + 24 : v }

    static func julian(_ y0: Int, _ m0: Int, _ d: Int) -> Double {
        var y = y0, m = m0
        if m <= 2 { y -= 1; m += 12 }
        let a = Double(y / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(d) + b - 1524.5
    }

    private static func sun(_ jd: Double) -> (decl: Double, eqt: Double) {
        let D = jd - 2451545.0
        let gg = fixA(357.529 + 0.98560028 * D)
        let q = fixA(280.459 + 0.98564736 * D)
        let L = fixA(q + 1.915 * sin(r(gg)) + 0.020 * sin(r(2 * gg)))
        let e = 23.439 - 0.00000036 * D
        let ra = fixH(g(atan2(cos(r(e)) * sin(r(L)), cos(r(L)))) / 15)
        return (g(asin(sin(r(e)) * sin(r(L)))), q / 15 - ra)
    }

    /// Times in local hours (0–24+) for the given civil date, location and UTC offset (hours).
    static func hours(y: Int, m: Int, d: Int, lat: Double, lng: Double, tz: Double, method: PrMethod, hanafi: Bool, ramadan: Bool) -> [PrPrayer: Double] {
        let jd = julian(y, m, d) - lng / (15 * 24)
        func mid(_ t: Double) -> Double { fixH(12 - sun(jd + t).eqt) }
        func angleTime(_ angle: Double, _ t: Double, _ ccw: Bool) -> Double {
            let dec = sun(jd + t).decl
            let noon = mid(t)
            let c = (-sin(r(angle)) - sin(r(dec)) * sin(r(lat))) / (cos(r(dec)) * cos(r(lat)))
            if c < -1 || c > 1 { return .nan }
            let tt = g(acos(c)) / 15
            return noon + (ccw ? -tt : tt)
        }
        func asr(_ f: Double, _ t: Double) -> Double {
            let dec = sun(jd + t).decl
            let ang = -g(atan(1 / (f + tan(r(abs(lat - dec))))))
            return angleTime(ang, t, false)
        }
        var t: [PrPrayer: Double] = [.fajr: 5, .sunrise: 6, .dhuhr: 12, .asr: 13, .maghrib: 18, .isha: 18]
        for _ in 0..<2 {
            let p = t.mapValues { ($0.isNaN ? 12 : $0) / 24 }
            t[.fajr] = angleTime(method.fajr, p[.fajr]!, true)
            t[.sunrise] = angleTime(0.833, p[.sunrise]!, true)
            t[.dhuhr] = mid(p[.dhuhr]!)
            t[.asr] = asr(hanafi ? 2 : 1, p[.asr]!)
            t[.maghrib] = angleTime(0.833, p[.maghrib]!, false)
            t[.isha] = method.isha.map { angleTime($0, p[.isha]!, false) } ?? 0
        }
        let adj = tz - lng / 15
        var out = t.mapValues { $0 + adj }
        if method.isha == nil {
            let extra = (method.id == "umm" && ramadan) ? 120.0 : method.ishaMinutes
            out[.isha] = out[.maghrib]! + extra / 60
        }
        return out
    }

    /// Actual moments for one day at a place.
    static func day(_ date: Date, lat: Double, lng: Double, zone: TimeZone, method: PrMethod, hanafi: Bool) -> [PrPrayer: Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let start = cal.date(from: c) ?? date
        let tz = Double(zone.secondsFromGMT(for: start.addingTimeInterval(12 * 3600))) / 3600
        var hc = Calendar(identifier: .islamicUmmAlQura)
        hc.timeZone = zone
        let ramadan = hc.component(.month, from: start.addingTimeInterval(12 * 3600)) == 9
        let h = hours(y: c.year ?? 2026, m: c.month ?? 1, d: c.day ?? 1, lat: lat, lng: lng, tz: tz, method: method, hanafi: hanafi, ramadan: ramadan)
        var out: [PrPrayer: Date] = [:]
        for (k, v) in h where !v.isNaN {
            let mins = (v * 60).rounded()
            out[k] = start.addingTimeInterval(mins * 60)
        }
        return out
    }
}
