import Foundation

/// The central database address and its PUBLIC (anon) key, injected at build time from the
/// GitHub repository variables. No secret key is ever in the app.
struct CloudConfig {
    let url: URL
    let anonKey: String

    static func fromBundle() -> CloudConfig? {
        let info = Bundle.main.infoDictionary ?? [:]
        let u = (info["SUPABASE_URL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let k = (info["SUPABASE_ANON_KEY"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard u.hasPrefix("https://"), !k.isEmpty, !u.contains("$("), let url = URL(string: u) else { return nil }
        return CloudConfig(url: url, anonKey: k)
    }
}
