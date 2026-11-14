import SwiftUI

extension Color {
    /// Builds a colour from the `RRGGBB` strings used in the city rulesets.
    ///
    /// Falls back to grey rather than crashing, because the rulesets are data and data
    /// can be wrong; a wrong colour is a cosmetic bug, a crash is not.
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

extension WasteStream {
    var color: Color { Color(hex: colorHex) }

    /// Bin colours are chosen by municipalities, not designers, and several of them
    /// (yellow, clear-glass grey) are unreadable behind white text. The decision comes
    /// from `prefersDarkSymbol`, which lives in the model layer so the resulting contrast
    /// can be asserted for every stream rather than eyeballed.
    var foregroundOnColor: Color {
        prefersDarkSymbol ? Color.black.opacity(0.85) : .white
    }

    var kindDescription: String {
        switch kind {
        case .recycling: "Recycling"
        case .organic: "Organic"
        case .residual: "Residual"
        case .deposit: "Refundable"
        case .dropOff: "Drop-off"
        }
    }
}

/// The coloured bin badge, used on verdict cards and in history.
struct StreamBadge: View {
    let stream: WasteStream
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(stream.color)
            .overlay {
                Image(systemName: stream.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(stream.foregroundOnColor)
            }
            .overlay {
                // Keeps pale streams such as Weißglas from vanishing into the card.
                Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A two-letter region marker, drawn rather than typed.
///
/// This replaces the emoji flag everywhere it affected layout. Flag emoji are composed
/// from regional-indicator pairs that the iOS Simulator cannot render — they come out as
/// two empty boxes that still take up space — so a chip reading "Sorting by 🇯🇵 Tokyo
/// rules" wrapped onto two lines there while looking fine on device. Drawing the code
/// means the interface is identical on a device, in the simulator and on the Mac.
struct RegionBadge: View {
    let code: String
    var size: CGFloat = 22

    /// The badge holds text, so it has to grow with the user's text size. At
    /// accessibility sizes a fixed-point badge shrinks to a speck beside the label it
    /// belongs to — correct in pixels, useless to the person who enlarged the text.
    @ScaledMetric(relativeTo: .subheadline) private var scale: CGFloat = 1

    private var scaledSize: CGFloat { size * scale }

    var body: some View {
        Text(code)
            .font(.system(size: scaledSize * 0.5, weight: .semibold, design: .rounded))
            .monospaced()
            .foregroundStyle(.secondary)
            .frame(width: scaledSize * 1.45, height: scaledSize)
            .background(.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: scaledSize * 0.28))
            .accessibilityHidden(true)
    }
}

/// A small pill used for origin, match quality and kind labels.
struct TagPill: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.caption2)
            }
            Text(text).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

extension ScannedProduct.Origin {
    var label: String {
        switch self {
        case .openFoodFacts: "Open Food Facts"
        case .offlineSample: "Offline sample"
        case .cache: "Saved on device"
        case .manual: "Described by you"
        }
    }

    var symbol: String {
        switch self {
        case .openFoodFacts: "antenna.radiowaves.left.and.right"
        case .offlineSample: "shippingbox"
        case .cache: "internaldrive"
        case .manual: "hand.tap"
        }
    }
}

