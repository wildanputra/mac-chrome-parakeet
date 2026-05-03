#if DEBUG
import SwiftUI

/// One-stop drift catcher for the MacParakeet design system. Renders every
/// button role, typography token, color, shadow, and spacing scale in a
/// single scrollable canvas so a 30-second visual sweep surfaces any token
/// that fell out of sync with the rest of the app.
///
/// Open with the SwiftUI canvas in Xcode (the `#Preview` at the bottom)
/// or instantiate directly inside a debug-only window.
///
/// Light/dark are exercised side-by-side via the canvas environment in
/// the preview block.
struct DesignSystemGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
                section("Buttons") { buttonRoles }
                section("Typography") { typographyScale }
                section("Colors") { colorSwatches }
                section("Shadows") { shadowSamples }
                section("Spacing") { spacingRulers }
                section("Layout radii") { radiiSamples }
            }
            .padding(DesignSystem.Spacing.xl)
        }
        .frame(minWidth: 760, minHeight: 800)
        .background(.thickMaterial)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttonRoles: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            roleRow(label: "primary", role: .primary)
            roleRow(label: "primary prominent", role: .primaryProminent)
            roleRow(label: "secondary", role: .secondary)
            roleRow(label: "destructive", role: .destructive)
            roleRow(label: "destructive prominent", role: .destructiveProminent)
            roleRow(label: "subtle", role: .subtle)
        }
    }

    private func roleRow(label: String, role: ParakeetActionRole) -> some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            Text(label)
                .font(DesignSystem.Typography.caption.monospaced())
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 200, alignment: .leading)
            Button("Action") { }
                .parakeetAction(role)
            Button("Disabled") { }
                .parakeetAction(role)
                .disabled(true)
            Spacer()
        }
    }

    // MARK: - Typography

    @ViewBuilder
    private var typographyScale: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            typeRow("heroTitle",      DesignSystem.Typography.heroTitle,      "28 / bold rounded")
            typeRow("pageTitle",      DesignSystem.Typography.pageTitle,      "22 / semibold rounded")
            typeRow("sectionTitle",   DesignSystem.Typography.sectionTitle,   "17 / semibold")
            typeRow("bodyLarge",      DesignSystem.Typography.bodyLarge,      "15")
            typeRow("body",           DesignSystem.Typography.body,           "14")
            typeRow("bodySmall",      DesignSystem.Typography.bodySmall,      "13")
            typeRow("caption",        DesignSystem.Typography.caption,        "12")
            typeRow("micro",          DesignSystem.Typography.micro,          "11")
            typeRow("timestamp",      DesignSystem.Typography.timestamp,      "12 monodigit · 12:34")
            typeRow("duration",       DesignSystem.Typography.duration,       "11 monodigit · 04:21")
        }
    }

    private func typeRow(_ name: String, _ font: Font, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.lg) {
            Text(name)
                .font(DesignSystem.Typography.caption.monospaced())
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 140, alignment: .leading)
            Text("The quick brown fox jumps")
                .font(font)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            Text(note)
                .font(DesignSystem.Typography.micro)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }

    // MARK: - Colors

    @ViewBuilder
    private var colorSwatches: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            colorGroup(
                title: "Brand",
                items: [
                    ("accent",      DesignSystem.Colors.accent),
                    ("accentLight", DesignSystem.Colors.accentLight),
                    ("accentDark",  DesignSystem.Colors.accentDark),
                ]
            )
            colorGroup(
                title: "Surfaces",
                items: [
                    ("background",       DesignSystem.Colors.background),
                    ("surface",          DesignSystem.Colors.surface),
                    ("surfaceElevated",  DesignSystem.Colors.surfaceElevated),
                    ("cardBackground",   DesignSystem.Colors.cardBackground),
                    ("rowHoverBackground", DesignSystem.Colors.rowHoverBackground),
                ]
            )
            colorGroup(
                title: "Text",
                items: [
                    ("textPrimary",   DesignSystem.Colors.textPrimary),
                    ("textSecondary", DesignSystem.Colors.textSecondary),
                    ("textTertiary",  DesignSystem.Colors.textTertiary),
                    ("tintNeutral",   DesignSystem.Colors.tintNeutral),
                ]
            )
            colorGroup(
                title: "Semantic",
                items: [
                    ("successGreen", DesignSystem.Colors.successGreen),
                    ("warningAmber", DesignSystem.Colors.warningAmber),
                    ("errorRed",     DesignSystem.Colors.errorRed),
                ]
            )
            colorGroup(
                title: "Lines",
                items: [
                    ("border",  DesignSystem.Colors.border),
                    ("divider", DesignSystem.Colors.divider),
                ]
            )
            colorGroup(
                title: "Speakers",
                items: DesignSystem.Colors.speakerColors.enumerated().map { idx, color in
                    ("speaker[\(idx)]", color)
                }
            )
        }
    }

    private func colorGroup(title: String, items: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title.uppercased())
                .font(DesignSystem.Typography.micro.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                ForEach(items, id: \.0) { name, color in
                    swatch(name: name, color: color)
                }
            }
        }
    }

    private func swatch(name: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(DesignSystem.Colors.border.opacity(0.6), lineWidth: 0.5)
                )
            Text(name)
                .font(DesignSystem.Typography.micro.monospaced())
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Shadows

    @ViewBuilder
    private var shadowSamples: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            shadowCard(label: "cardRest",    style: DesignSystem.Shadows.cardRest)
            shadowCard(label: "cardHover",   style: DesignSystem.Shadows.cardHover)
            shadowCard(label: "portalLift",  style: DesignSystem.Shadows.portalLift)
            shadowCard(label: "meetingPill", style: DesignSystem.Shadows.meetingPill)
        }
    }

    private func shadowCard(label: String, style: ShadowStyle) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(DesignSystem.Colors.cardBackground)
                .frame(width: 140, height: 80)
                .cardShadow(style)
            Text(label)
                .font(DesignSystem.Typography.micro.monospaced())
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Spacing

    @ViewBuilder
    private var spacingRulers: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            spacingRow("xs",  DesignSystem.Spacing.xs)
            spacingRow("sm",  DesignSystem.Spacing.sm)
            spacingRow("md",  DesignSystem.Spacing.md)
            spacingRow("lg",  DesignSystem.Spacing.lg)
            spacingRow("xl",  DesignSystem.Spacing.xl)
            spacingRow("xxl", DesignSystem.Spacing.xxl)
            spacingRow("hero", DesignSystem.Spacing.hero)
        }
    }

    private func spacingRow(_ name: String, _ value: CGFloat) -> some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            Text(name)
                .font(DesignSystem.Typography.caption.monospaced())
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 60, alignment: .leading)
            Rectangle()
                .fill(DesignSystem.Colors.accent)
                .frame(width: value, height: 12)
            Text("\(Int(value))pt")
                .font(DesignSystem.Typography.micro.monospaced())
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Spacer()
        }
    }

    // MARK: - Layout radii

    @ViewBuilder
    private var radiiSamples: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            radiusCard("cornerRadius",     DesignSystem.Layout.cornerRadius)
            radiusCard("cardCornerRadius", DesignSystem.Layout.cardCornerRadius)
            radiusCard("rowCornerRadius",  DesignSystem.Layout.rowCornerRadius)
            radiusCard("buttonCorner",     DesignSystem.Layout.buttonCornerRadius)
        }
    }

    private func radiusCard(_ name: String, _ radius: CGFloat) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            RoundedRectangle(cornerRadius: radius)
                .fill(DesignSystem.Colors.surfaceElevated)
                .frame(width: 100, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
                )
            VStack(spacing: 0) {
                Text(name)
                    .font(DesignSystem.Typography.micro.monospaced())
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("\(Int(radius))pt")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
    }

    // MARK: - Section frame

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(title)
                .font(DesignSystem.Typography.sectionTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            content()
        }
    }
}

#Preview("DesignSystem · Dark") {
    DesignSystemGalleryView()
        .preferredColorScheme(.dark)
}

#Preview("DesignSystem · Light") {
    DesignSystemGalleryView()
        .preferredColorScheme(.light)
}
#endif
