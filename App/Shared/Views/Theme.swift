import AgentCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

// Kith's design system: one palette, one type voice, one mark. See docs/brand/BRAND.md.
//
// The palette is warm and quiet on purpose: an assistant over your own calendar should feel
// like paper and ink, not like a dashboard. Colour carries meaning and is never decoration:
// moss is Kith and "on this device", leaf is "checked against your data", amber is "waiting
// for your OK", coral is "stopped", and each place an answer can run has its own colour.

extension Color {
    /// A colour with a light and a dark value, resolved by the system.
    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
            self.init(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        #else
            self.init(uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            })
        #endif
    }

    // Grounds
    static let kithPaper = Color(light: 0xF5F1E8, dark: 0x111815)     // the window
    static let kithSurface = Color(light: 0xFFFDF8, dark: 0x19221E)   // cards, composer
    static let kithSunken = Color(light: 0xEDE7DA, dark: 0x0C110F)    // wells, trace
    static let kithLine = Color(light: 0xE2DACB, dark: 0x27332D)      // hairlines
    static let kithInk = Color(light: 0x18241E, dark: 0xEEF0EA)       // text
    static let kithMuted = Color(light: 0x5E6A62, dark: 0x9AA8A0)     // secondary text

    // Meaning
    static let kithMoss = Color(light: 0x2F6E57, dark: 0x5FB394)      // Kith, on device
    static let kithLeaf = Color(light: 0x2E8A5E, dark: 0x6CC596)      // checked
    static let kithAmber = Color(light: 0xC27E16, dark: 0xF0B456)     // waiting for your OK
    static let kithCoral = Color(light: 0xC4502C, dark: 0xF08766)     // blocked, withheld
    static let kithDusk = Color(light: 0x4F5BC4, dark: 0x8E99F2)      // your Mac
    static let kithClay = Color(light: 0xB8613B, dark: 0xE79A74)      // Claude
}

#if os(macOS)
    extension NSColor {
        convenience init(hex: UInt32) {
            self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                      blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
#else
    extension UIColor {
        convenience init(hex: UInt32) {
            self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                      blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
#endif

extension Tier {
    /// Where an answer ran, as a colour: the same in the footer, the trace and the welcome.
    var tint: Color {
        switch self {
        case .onDevice: return .kithMoss
        case .localOpen: return .kithDusk
        case .claude: return .kithClay
        }
    }
}

// MARK: - Type

extension Font {
    /// Display type: SF Pro Rounded, heavy. Used for titles only.
    static func kithDisplay(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

// MARK: - The mark

/// The Kith mark, drawn as vectors so it is sharp at any size: a lowercase k whose raised arm
/// reaches toward a dot, someone you know waving. Same geometry as docs/brand/*.svg (1024 grid).
struct KithGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let o = CGPoint(x: rect.midX - 512 * s, y: rect.midY - 512 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        path.move(to: p(356, 300)); path.addLine(to: p(356, 730))
        path.move(to: p(356, 604)); path.addLine(to: p(538, 443))
        path.move(to: p(474, 508)); path.addLine(to: p(640, 730))
        return path.strokedPath(StrokeStyle(lineWidth: 118 * s, lineCap: .round, lineJoin: .round))
    }
}

struct KithDot: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let o = CGPoint(x: rect.midX - 512 * s, y: rect.midY - 512 * s)
        let r = 86 * s
        return Path(ellipseIn: CGRect(x: o.x + 652 * s - r, y: o.y + 322 * s - r, width: 2 * r, height: 2 * r))
    }
}

/// The mark on its moss tile, like the app icon.
struct KithMark: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(light: 0x3C8068, dark: 0x3C8068), Color(light: 0x22503F, dark: 0x22503F)],
                                     startPoint: .top, endPoint: .bottom))
            KithGlyph().fill(Color(light: 0xF5F1E8, dark: 0xF5F1E8))
            KithDot().fill(Color(light: 0xE9A23B, dark: 0xE9A23B))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

extension View {
    /// A card on the paper ground: surface colour, soft corners, one hairline.
    func kithCard(radius: CGFloat = 16, padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Color.kithSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.kithLine))
    }
}

/// Kith's main button: a filled moss capsule.
struct KithProminentButtonStyle: ButtonStyle {
    var tint: Color = .kithMoss

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(tint.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// The quiet partner of the main button.
struct KithQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.kithInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.kithSunken.opacity(configuration.isPressed ? 1 : 0.8), in: Capsule())
    }
}
