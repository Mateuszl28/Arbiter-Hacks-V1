import SwiftUI

extension Color {
    /// Builds a colour from the `RRGGBB` strings used in the city rulesets.
    ///
    /// Lives in Shared because the widget draws bin colours too, and a widget that
    /// disagreed with the app about what "yellow bin" looks like would be worse than no
    /// widget. Falls back to grey rather than crashing: the rulesets are data, and data
    /// can be wrong; a wrong colour is cosmetic, a crash is not.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
