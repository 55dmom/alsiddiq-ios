import SwiftUI

/// Added by the host app «مركز الصديق»: its «الثيمات» can hand this button an accent / soft / background colour
/// (UserDefaults keys alsiddiq.toolPalette.*). With no key set, the button keeps its own colours. Texts and logic untouched.
enum HostPalette {
    static func color(_ key: String) -> Color? {
        let k = "alsiddiq.toolPalette." + key
        guard UserDefaults.standard.object(forKey: k) != nil else { return nil }
        let v = UInt32(truncatingIfNeeded: UserDefaults.standard.integer(forKey: k))
        return Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}
