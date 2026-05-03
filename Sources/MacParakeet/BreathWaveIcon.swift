import AppKit

/// Generates the MacParakeet "Cursive P" logo programmatically.
///
/// Design: An enclosed circular bowl with a dot inside, and a cursive loop tail
/// that descends, loops under, and trails off left. The loop echoes the bowl's
/// circular rhythm — two circles in harmony.
///
/// Inspired by Daoist simplicity: a single stroke forming a P with a bird's-eye
/// dot at center. The cursive tail gives it handwritten warmth.
///
/// The icon is drawn via Core Graphics so it scales perfectly at any size
/// and works as a template image (adapts to light/dark mode automatically).
enum BreathWaveIcon {

    // MARK: - Canonical Geometry (128×128 viewBox)

    // Bowl: circle cx=68, cy=34, r=26
    // Dot: cx=68, cy=34, r=6
    // Stem + cursive loop tail:
    //   M 42,34 L 42,82 C 42,100 30,110 18,112 C 6,114 2,106 8,98 C 14,90 30,88 42,92
    // Stroke width: 7 (large), 10 (small/menu bar)

    /// Menu bar icon state variants.
    enum MenuBarState {
        case idle
        case recording
        case processing
    }

    /// Load the parakeet silhouette as a **template** NSImage for menu bar use.
    /// The image is stored as a processed SwiftPM resource (menubar-icon.png / @2x).
    /// Template images adapt to light/dark mode automatically.
    static func menuBarIcon(pointSize: CGFloat = 18, state: MenuBarState = .idle) -> NSImage {
        let baseIcon = loadBaseMenuBarIcon(pointSize: pointSize)

        switch state {
        case .idle:
            return baseIcon
        case .recording:
            return compositeIcon(base: baseIcon, pointSize: pointSize, badgeColor: .systemRed)
        case .processing:
            return compositeIcon(base: baseIcon, pointSize: pointSize, badgeColor: .systemOrange)
        }
    }

    private static func loadBaseMenuBarIcon(pointSize: CGFloat) -> NSImage {
        // Try loading from SwiftPM resource bundle first, then fall back to main bundle.
        if let url = Bundle.module.url(forResource: "menubar-icon@2x", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: pointSize, height: pointSize)
            image.isTemplate = true
            return image
        }

        // Fallback: 1x version
        if let url = Bundle.module.url(forResource: "menubar-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: pointSize, height: pointSize)
            image.isTemplate = true
            return image
        }

        // Last resort: return a system symbol
        let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MacParakeet")
            ?? NSImage()
        fallback.size = NSSize(width: pointSize, height: pointSize)
        fallback.isTemplate = true
        return fallback
    }

    /// Composite the base icon with a colored status dot in the bottom-right corner.
    /// The resulting image is NOT a template (so the dot renders in color).
    /// The base icon is drawn using the menu bar's label color so it matches
    /// the idle template appearance in both light and dark mode.
    private static func compositeIcon(base: NSImage, pointSize: CGFloat, badgeColor: NSColor) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            // Use the base icon alpha channel as a mask, filled with the menu bar
            // foreground color. This replicates template-image rendering while keeping
            // isTemplate=false so the colored dot isn't tinted by the system.
            // NSStatusBar items use controlTextColor which is white on dark menu bars
            // and black on light ones (pre-Sonoma or accessibility settings).
            if let cgBase = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.clip(to: rect, mask: cgBase)
                NSColor.controlTextColor.setFill()
                ctx.fill(rect)
                ctx.restoreGState()
            }

            // Draw colored dot (bottom-right, 5pt diameter)
            let dotSize: CGFloat = 5
            let dotRect = NSRect(
                x: rect.maxX - dotSize - 0.5,
                y: 0.5,
                width: dotSize,
                height: dotSize
            )
            badgeColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        // NOT a template — the dot must render in color
        image.isTemplate = false
        return image
    }

    /// Render the bare Cursive P brand mark as a transparent template NSImage,
    /// suitable for inline tinting in SwiftUI views (assistant avatars, status
    /// chips, etc.). No background, no padding — just the alpha-channel
    /// silhouette — so callers control color via `.renderingMode(.template)` +
    /// `.foregroundStyle()`.
    ///
    /// Uses the canonical 128-viewBox geometry from `docs/brand-identity.md`
    /// with the small-size stroke/dot spec (10 / radius 8) for legibility at
    /// 16-32pt display sizes. Rendered at 4× the logical point size so SwiftUI
    /// can downscale crisply at retina without anti-aliasing fuzz that runtime
    /// vector strokes show at sub-2pt widths.
    ///
    /// The visual content (~96×116 inside the 128 viewBox) is centered into
    /// the pixel canvas — the canonical glyph is biased upper-right within
    /// 128, so a naïve `size/128` scale would push the mark off-center in
    /// any tight inline frame.
    static func brandMark(pointSize: CGFloat = 18) -> NSImage {
        let scaleFactor: CGFloat = 4
        let pixel = pointSize * scaleFactor
        let image = NSImage(size: NSSize(width: pixel, height: pixel), flipped: true) { _ in
            let visualW: CGFloat = 96
            let visualH: CGFloat = 116
            let visualMinX: CGFloat = 3
            let visualMinY: CGFloat = 3
            let fit = min(pixel / visualW, pixel / visualH)
            let offsetX = (pixel - visualW * fit) / 2 - visualMinX * fit
            let offsetY = (pixel - visualH * fit) / 2 - visualMinY * fit

            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: offsetX, y: offsetY)
            ctx.scaleBy(x: fit, y: fit)

            // Template image — only the alpha channel matters; tint flows
            // through SwiftUI's `.foregroundStyle` on the consuming view.
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Bowl
            let bowl = NSBezierPath(ovalIn: NSRect(x: 42, y: 8, width: 52, height: 52))
            bowl.lineWidth = 10
            bowl.stroke()

            // Stem + cursive loop tail
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 42, y: 34))
            tail.line(to: NSPoint(x: 42, y: 82))
            tail.curve(
                to: NSPoint(x: 18, y: 112),
                controlPoint1: NSPoint(x: 42, y: 100),
                controlPoint2: NSPoint(x: 30, y: 110)
            )
            tail.curve(
                to: NSPoint(x: 8, y: 98),
                controlPoint1: NSPoint(x: 6, y: 114),
                controlPoint2: NSPoint(x: 2, y: 106)
            )
            tail.curve(
                to: NSPoint(x: 42, y: 92),
                controlPoint1: NSPoint(x: 14, y: 90),
                controlPoint2: NSPoint(x: 30, y: 88)
            )
            tail.lineWidth = 10
            tail.lineCapStyle = .round
            tail.lineJoinStyle = .round
            tail.stroke()

            // Dot
            NSBezierPath(ovalIn: NSRect(x: 60, y: 26, width: 16, height: 16)).fill()

            return true
        }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }

    /// Create the Cursive P logo as a filled NSImage for app icon / dock use.
    /// Uses white on a colored background.
    static func appIcon(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let s = size / 128.0
            let cornerRadius = 22 * s

            // Background — deep teal-blue gradient
            let bg = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            let gradient = NSGradient(
                starting: NSColor(red: 0.12, green: 0.20, blue: 0.32, alpha: 1.0),
                ending: NSColor(red: 0.08, green: 0.14, blue: 0.24, alpha: 1.0)
            )
            gradient?.draw(in: bg, angle: -90)

            // White logo, centered with padding
            let padding: CGFloat = 20 * s
            let ls = (size - padding * 2) / 128.0

            NSColor.white.setStroke()
            NSColor.white.setFill()

            let bowlRadius = 26 * ls

            // Enclosed circular bowl
            let bowl = NSBezierPath(
                ovalIn: NSRect(
                    x: padding + 68 * ls - bowlRadius, y: padding + 34 * ls - bowlRadius,
                    width: bowlRadius * 2, height: bowlRadius * 2
                )
            )
            bowl.lineWidth = 7 * ls
            bowl.stroke()

            // Stem + cursive loop tail
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: padding + 42 * ls, y: padding + 34 * ls))
            tail.line(to: NSPoint(x: padding + 42 * ls, y: padding + 82 * ls))
            tail.curve(
                to: NSPoint(x: padding + 18 * ls, y: padding + 112 * ls),
                controlPoint1: NSPoint(x: padding + 42 * ls, y: padding + 100 * ls),
                controlPoint2: NSPoint(x: padding + 30 * ls, y: padding + 110 * ls)
            )
            tail.curve(
                to: NSPoint(x: padding + 8 * ls, y: padding + 98 * ls),
                controlPoint1: NSPoint(x: padding + 6 * ls, y: padding + 114 * ls),
                controlPoint2: NSPoint(x: padding + 2 * ls, y: padding + 106 * ls)
            )
            tail.curve(
                to: NSPoint(x: padding + 42 * ls, y: padding + 92 * ls),
                controlPoint1: NSPoint(x: padding + 14 * ls, y: padding + 90 * ls),
                controlPoint2: NSPoint(x: padding + 30 * ls, y: padding + 88 * ls)
            )
            tail.lineWidth = 7 * ls
            tail.lineCapStyle = .round
            tail.stroke()

            // Dot
            let dotRadius = 6 * ls
            NSBezierPath(ovalIn: NSRect(
                x: padding + 68 * ls - dotRadius, y: padding + 34 * ls - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            )).fill()

            return true
        }
        return image
    }
}
