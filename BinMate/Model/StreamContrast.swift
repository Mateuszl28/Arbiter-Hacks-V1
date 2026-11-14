import Foundation

/// Decides whether a stream's symbol should be drawn dark or light, and how readable the
/// result is.
///
/// Bin colours are chosen by municipalities, not designers. Berlin's `Gelbe Tonne` is a
/// bright yellow and its `Weißglas` is a pale grey; white symbols vanish on both. The
/// decision is made from relative luminance rather than taste, and because this lives in
/// the model layer rather than beside the views, the resulting contrast is asserted in
/// the test suite for every stream of every city instead of being eyeballed in a
/// screenshot.
extension WasteStream {
    /// sRGB components in 0...1, or nil when `colorHex` is malformed.
    var rgbComponents: (red: Double, green: Double, blue: Double)? {
        let cleaned = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// WCAG relative luminance.
    var relativeLuminance: Double {
        guard let rgb = rgbComponents else { return 0 }
        func channel(_ srgb: Double) -> Double {
            srgb <= 0.03928 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.red) + 0.7152 * channel(rgb.green) + 0.0722 * channel(rgb.blue)
    }

    /// Whether a dark symbol reads better than a white one on this bin colour.
    ///
    /// Measured, not guessed. An earlier version used a fixed luminance threshold, which
    /// is the obvious approach and quietly wrong for mid-tones: Berlin's pale `Weißglas`
    /// grey and Tokyo's amber both sat just under the cut-off and got a white symbol at
    /// about 2.3–2.6:1, well below legible. Computing both candidates and keeping the
    /// better one has no such blind spot, and needs no threshold to argue about.
    var prefersDarkSymbol: Bool {
        guard rgbComponents != nil else { return false }
        return contrastRatio(symbolLuminance: darkSymbolLuminance)
            > contrastRatio(symbolLuminance: 1.0)
    }

    /// WCAG contrast ratio of the symbol actually drawn, 1...21.
    var symbolContrastRatio: Double {
        contrastRatio(symbolLuminance: prefersDarkSymbol ? darkSymbolLuminance : 1.0)
    }

    /// The symbol is black at 85% opacity, so what lands on screen is partly the bin
    /// colour showing through. Measuring the ideal black would overstate the contrast.
    private var darkSymbolLuminance: Double {
        relativeLuminance * 0.15
    }

    private func contrastRatio(symbolLuminance: Double) -> Double {
        let background = relativeLuminance
        let lighter = max(symbolLuminance, background)
        let darker = min(symbolLuminance, background)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
