import AppKit
import SwiftUI

/// MacParakeet's "Cursive P" / Breath Wave brand mark for inline use in
/// SwiftUI views — assistant avatars, status chips, future brand-anchored
/// surfaces. Backed by `BreathWaveIcon.brandMark`, which renders the
/// canonical 128-viewBox geometry into a 4×-resolution template NSImage via
/// AppKit Core Graphics. SwiftUI then downscales crisply with high
/// interpolation and tints via `.foregroundStyle()`.
///
/// ## Why not a SwiftUI Canvas
/// An earlier version drew the mark with `Canvas` + `Path.stroke` at the
/// display size. Below ~24pt, runtime vector strokes at sub-2pt widths
/// anti-alias unevenly — the bowl reads as oval-ish, the dot looks soft, the
/// whole mark feels a half-grade off the menubar's hand-tuned appearance.
/// Pre-rasterizing at 4× and downscaling delegates the hard part (small-size
/// hinting) to AppKit's mature CG path, which the dock icon already trusts.
///
/// ## Sizing guidance
/// `docs/brand-identity.md` documents 16px as the legibility floor and 18px
/// as the menubar's tested target. Default size here is 18pt to land on the
/// known-good rung; consumers can request smaller, but expect quality to
/// drop quickly below 14pt.
struct BreathWaveLogo: View {
    var size: CGFloat = 18
    var tint: Color = DesignSystem.Colors.accent
    var opacity: Double = 1.0

    var body: some View {
        Image(nsImage: Self.cachedMark)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: size, height: size)
            .foregroundStyle(tint.opacity(opacity))
            .accessibilityHidden(true)
    }

    /// Process-lifetime cache. The template NSImage is built once at first
    /// access; subsequent BreathWaveLogo instances reuse the same alpha
    /// raster and only re-tint via SwiftUI. Rendered at 18pt logical so the
    /// 4× source (72px) covers any 12-24pt display without re-rasterization.
    private static let cachedMark: NSImage = BreathWaveIcon.brandMark(pointSize: 18)
}
